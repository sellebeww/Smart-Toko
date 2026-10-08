// Edge Function: mengurai ucapan transaksi yang gagal diurai parser lokal.
//
// Kunci API Anthropic hanya hidup di sini (secret ANTHROPIC_API_KEY), tidak
// pernah di aplikasi. Fungsi ini hanya menerima transkrip — bukan permintaan
// bebas ke model — jadi tidak bisa dipakai sebagai proxy umum. Pemakaian
// dibatasi per pengguna per hari lewat `consume_llm_quota` (lihat setup.sql).
//
// Deploy:
//   supabase secrets set ANTHROPIC_API_KEY=sk-ant-...
//   supabase functions deploy parse-transaction
//
// JWT pengguna diverifikasi oleh platform (verify_jwt bawaan aktif), dan
// diteruskan ke Postgres supaya auth.uid() di fungsi kuota terisi.

import Anthropic from "npm:@anthropic-ai/sdk";
import { createClient } from "npm:@supabase/supabase-js@2";

const MODEL = "claude-opus-5-5";
const DAILY_LIMIT = Number(Deno.env.get("LLM_DAILY_LIMIT") ?? "200");
const MAX_TRANSCRIPT_CHARS = 500;

const SYSTEM_PROMPT = `Kamu membantu mengurai ucapan pemilik warung di Indonesia menjadi data transaksi.

Aturan:
- Hanya ekstrak yang benar-benar terdengar. JANGAN mengarang nama barang, jumlah, atau harga.
- Bila arah transaksi tidak jelas, isi "tidak_yakin". Jangan menebak.
- Bila jumlah tidak disebut, gunakan 1.
- Bila harga tidak disebut, isi null. Jangan memperkirakan harga pasar.
- Harga dalam rupiah penuh sebagai bilangan bulat: "lima ribu" -> 5000, "25rb" -> 25000.
- "keyakinan" adalah penilaian jujurmu 0..1 atas keseluruhan hasil. Turunkan nilainya bila ucapan ambigu atau terpotong.

Hasil akhirnya akan selalu ditampilkan ke pengguna untuk dikonfirmasi sebelum disimpan, jadi lebih baik mengaku tidak tahu daripada menebak.

Pengguna sedang menunggu; langsung berikan jawaban.`;

const nullable = (type: string, description: string) => ({
  anyOf: [{ type }, { type: "null" }],
  description,
});

const OUTPUT_SCHEMA = {
  type: "object",
  additionalProperties: false,
  properties: {
    arah: {
      type: "string",
      enum: ["masuk", "keluar", "tidak_yakin"],
      description: "masuk = penjualan/pemasukan, keluar = pembelian/pengeluaran",
    },
    barang: {
      type: "array",
      description: "Daftar barang yang disebut. Boleh kosong.",
      items: {
        type: "object",
        additionalProperties: false,
        properties: {
          nama: nullable("string", "Nama barang apa adanya, null bila tidak disebut"),
          jumlah: nullable("integer", "Kuantitas, null bila tidak disebut"),
          harga_satuan: nullable(
            "integer",
            "Harga per unit dalam rupiah, null bila tidak disebut",
          ),
        },
        required: ["nama", "jumlah", "harga_satuan"],
      },
    },
    keyakinan: { type: "number", description: "Keyakinan keseluruhan, 0 sampai 1" },
  },
  required: ["arah", "barang", "keyakinan"],
};

const anthropic = new Anthropic({
  apiKey: Deno.env.get("ANTHROPIC_API_KEY"),
  timeout: 15_000,
  maxRetries: 1,
});

function json(status: number, body: unknown): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json" },
  });
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return json(405, { error: "method_not_allowed" });

  const authHeader = req.headers.get("Authorization");
  if (!authHeader) return json(401, { error: "unauthorized" });

  let transcript: unknown;
  try {
    ({ transcript } = await req.json());
  } catch {
    return json(400, { error: "invalid_body" });
  }
  if (
    typeof transcript !== "string" ||
    transcript.trim().length === 0 ||
    transcript.length > MAX_TRANSCRIPT_CHARS
  ) {
    return json(400, { error: "invalid_transcript" });
  }

  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_ANON_KEY")!,
    { global: { headers: { Authorization: authHeader } } },
  );
  const { data: allowed, error: quotaError } = await supabase.rpc(
    "consume_llm_quota",
    { p_daily_limit: DAILY_LIMIT },
  );
  if (quotaError) return json(502, { error: "quota_check_failed" });
  if (allowed !== true) return json(429, { error: "daily_limit_reached" });

  // Kegagalan di sisi server/model bukan salah pengguna: jatah dikembalikan.
  const refund = async () => {
    try {
      await supabase.rpc("refund_llm_quota");
    } catch (_) {
      // Pengembalian jatah bersifat upaya terbaik.
    }
  };

  try {
    const response = await anthropic.beta.messages.create({
      model: MODEL,
      max_tokens: 2048,
      betas: ["server-side-fallback-2026-07-01"],
      // @ts-ignore: bentuk "default" bisa belum ada di tipe SDK.
      fallbacks: "default",
      output_config: {
        effort: "low",
        format: { type: "json_schema", schema: OUTPUT_SCHEMA },
      },
      system: SYSTEM_PROMPT,
      messages: [
        {
          role: "user",
          content:
            "Ucapan pengguna (hasil speech-to-text, mungkin mengandung salah dengar):\n" +
            JSON.stringify(transcript.trim()),
        },
      ],
    });

    // Penolakan model tetap datang sebagai HTTP 200.
    if (response.stop_reason === "refusal") {
      await refund();
      return json(422, { error: "refused" });
    }
    if (response.stop_reason === "max_tokens") {
      await refund();
      return json(502, { error: "truncated" });
    }

    const text = response.content.find((block) => block.type === "text");
    if (!text || text.type !== "text") {
      await refund();
      return json(502, { error: "no_output" });
    }

    return json(200, { result: JSON.parse(text.text) });
  } catch (error) {
    await refund();
    if (error instanceof Anthropic.RateLimitError) {
      return json(503, { error: "upstream_busy" });
    }
    if (error instanceof Anthropic.APIConnectionError) {
      return json(504, { error: "upstream_unreachable" });
    }
    if (error instanceof Anthropic.APIError) {
      return json(502, { error: "upstream_error", status: error.status });
    }
    return json(500, { error: "internal" });
  }
});
