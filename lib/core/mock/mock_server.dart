import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'mock_engine.dart';

/// เซิร์ฟเวอร์ HTTP บนเครื่องนี้ (127.0.0.1 เท่านั้น — เครื่องอื่นในเครือข่ายเรียกไม่ได้) ที่ให้ [MockEngine] ตอบคำขอ
class MockServer {
  MockServer(this.engine, {this.onEntry});

  final MockEngine engine;

  /// เรียกเมื่อตอบคำขอแต่ละครั้ง
  final void Function(MockLogEntry entry)? onEntry;

  HttpServer? _server;

  /// ขนาด body สูงสุดที่รับ
  static const maxBody = 2 * 1024 * 1024;

  bool get running => _server != null;

  /// พอร์ตที่ฟังอยู่จริง (null = ไม่ได้รัน) ; ขอพอร์ต 0 = ระบบเลือกให้
  int? get port => _server?.port;

  /// เริ่มฟังที่ [port] ; พอร์ตถูกใช้อยู่ = โยน [SocketException]
  Future<void> start(int port) async {
    if (_server != null) return;
    final s = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
    _server = s;
    s.listen(_handle, onError: (_) {});
  }

  /// หยุดและปล่อยพอร์ต (ตัดการเชื่อมต่อที่ค้างอยู่ด้วย)
  Future<void> stop() async {
    final s = _server;
    _server = null;
    await s?.close(force: true);
  }

  static const _cors = {
    'access-control-allow-origin': '*',
    'access-control-allow-headers': '*',
    'access-control-allow-methods': 'GET, POST, PUT, PATCH, DELETE, OPTIONS',
    'x-nsl-mock': '1',
  };

  Future<void> _handle(HttpRequest req) async {
    final sw = Stopwatch()..start();
    final res = req.response;
    try {
      if (req.method == 'OPTIONS') {
        _cors.forEach(res.headers.set);
        res.statusCode = 204;
        return;
      }
      if (req.contentLength > maxBody) {
        _write(res, 413, '{"error":"payload_too_large"}', const {});
        return;
      }
      final bytes = <int>[];
      var tooBig = false;
      await for (final chunk in req) {
        bytes.addAll(chunk);
        if (bytes.length > maxBody) {
          tooBig = true;
          break;
        }
      }
      if (tooBig) {
        _write(res, 413, '{"error":"payload_too_large"}', const {});
        return;
      }
      final headers = <String, String>{};
      req.headers.forEach((name, values) => headers[name] = values.join(','));
      final result = engine.handle(MockRequest(
        method: req.method,
        path: req.uri.path,
        query: req.uri.queryParameters,
        headers: headers,
        body: utf8.decode(bytes, allowMalformed: true),
      ));
      final delay = result.reply.delay;
      if (delay > Duration.zero) await Future<void>.delayed(delay);
      _write(res, result.reply.status, result.reply.body, result.reply.headers);
      result.entry.durationMs = sw.elapsedMilliseconds;
      onEntry?.call(result.entry);
    } catch (_) {
      try {
        _write(res, 500, '{"error":"mock_internal_error"}', const {});
      } catch (_) {}
    } finally {
      try {
        await res.close();
      } catch (_) {}
    }
  }

  static void _write(HttpResponse res, int status, String body, Map<String, String> headers) {
    _cors.forEach(res.headers.set);
    headers.forEach(res.headers.set);
    res.statusCode = status;
    if (body.isNotEmpty) {
      res.headers.contentType = ContentType('application', 'json', charset: 'utf-8');
      res.add(utf8.encode(body));
    }
  }
}
