/// Pembungkus status koneksi.
///
/// Catatan penting: connectivity_plus melaporkan ADA TIDAKNYA antarmuka
/// jaringan, bukan apakah internet benar-benar bisa dijangkau. WiFi warung yang
/// terhubung tapi tidak membayar tagihan tetap dilaporkan "online". Karena itu
/// status di sini hanya dipakai untuk memutuskan apakah LAYAK mencoba; kepastian
/// tetap datang dari hasil percobaannya sendiri, dan kegagalan ditangani
/// backoff.
library;

import 'package:connectivity_plus/connectivity_plus.dart';

abstract class ConnectivityService {
  Future<bool> isOnline();

  Stream<bool> get onStatusChange;
}

class ConnectivityPlusService implements ConnectivityService {
  final Connectivity _connectivity;

  ConnectivityPlusService({Connectivity? connectivity})
    : _connectivity = connectivity ?? Connectivity();

  static bool _hasNetwork(List<ConnectivityResult> results) =>
      results.any((r) => r != ConnectivityResult.none);

  @override
  Future<bool> isOnline() async =>
      _hasNetwork(await _connectivity.checkConnectivity());

  @override
  Stream<bool> get onStatusChange =>
      _connectivity.onConnectivityChanged.map(_hasNetwork);
}

class FakeConnectivityService implements ConnectivityService {
  bool online;

  FakeConnectivityService({this.online = true});

  @override
  Future<bool> isOnline() async => online;

  @override
  Stream<bool> get onStatusChange => Stream<bool>.value(online);
}
