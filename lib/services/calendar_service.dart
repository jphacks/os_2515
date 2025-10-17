import 'package:http/http.dart' as http;
import 'package:googleapis/calendar/v3.dart' as gcal;
import 'auth_service.dart';

class CalendarService {
  final AuthService _authService;
  CalendarService(this._authService);

  Future<void> updateEventStart({
    required String eventId,
    required DateTime newStart,
    DateTime? newEnd,
  }) async {
    final api = await _api(); // 既存の認可済みクライアント取得メソッド
    final ev = gcal.Event(
      start: gcal.EventDateTime(dateTime: newStart.toUtc()),
      end: gcal.EventDateTime(
        dateTime: (newEnd ?? newStart.add(const Duration(hours: 1))).toUtc(),
      ),
    );
    await api.events.patch(ev, 'primary', eventId);
  }

  Future<void> updateEventTitle({
    required String eventId,
    required String newTitle,
  }) async {
    final api = await _api();
    final ev = gcal.Event(summary: newTitle);
    await api.events.patch(ev, 'primary', eventId);
  }

  Future<gcal.CalendarApi> _api() async {
    final headers = await _authService.calendarAuthHeaders();
    final client = _AuthorizedClient(headers);
    return gcal.CalendarApi(client);
  }

  // ToDo を Google カレンダーへ作成
  Future<String> createEvent({
    required String summary,
    required DateTime start,
    DateTime? end,
    String? description,
  }) async {
    final api = await _api();
    final event = gcal.Event(
      summary: '[TODO] $summary',
      description: description,
      start: gcal.EventDateTime(dateTime: start.toUtc()),
      end: gcal.EventDateTime(
        dateTime: (end ?? start.add(const Duration(hours: 1))).toUtc(),
      ),
      extendedProperties: gcal.EventExtendedProperties(
        private: {'source': 'todo-app'},
      ),
    );
    final created = await api.events.insert(event, 'primary');
    return created.id!; // eventId
  }

  // イベント更新
  Future<void> updateEvent({
    required String eventId,
    required String summary,
    required DateTime start,
    DateTime? end,
    String? description,
  }) async {
    final api = await _api();
    final event = await api.events.get('primary', eventId);
    event.summary = '[TODO] $summary';
    event.description = description;
    event.start = gcal.EventDateTime(dateTime: start.toUtc());
    event.end = gcal.EventDateTime(
      dateTime: (end ?? start.add(const Duration(hours: 1))).toUtc(),
    );
    await api.events.update(event, 'primary', eventId);
  }

  // イベント削除
  Future<void> deleteEvent(String eventId) async {
    final api = await _api();
    await api.events.delete('primary', eventId);
  }

  // カレンダーから TODO 候補を読み込む（[TODO] でフィルタ）
  Future<List<gcal.Event>> fetchTodoEvents({
    required DateTime from,
    required DateTime to,
  }) async {
    final api = await _api();
    final res = await api.events.list(
      'primary',
      timeMin: from.toUtc(),
      timeMax: to.toUtc(),
      singleEvents: true,
      orderBy: 'startTime',
      q: '[TODO] ',
    );
    return res.items ?? <gcal.Event>[];
  }
}

// シンプルな認可付き HTTP クライアント
class _AuthorizedClient extends http.BaseClient {
  final Map<String, String> _headers;
  final http.Client _inner = http.Client();
  _AuthorizedClient(this._headers);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    request.headers.addAll(_headers);
    return _inner.send(request);
  }
}
