import '../../domain/entities/conversation.dart';
import '../../domain/repositories/messages_repository.dart';
import '../data_sources/local/messages_mock_ds.dart';

/// Mock-backed implementation. Swap the data source for a remote one when the
/// API lands — the interface and every caller stay the same.
class MessagesRepositoryImpl implements MessagesRepository {
  const MessagesRepositoryImpl(this._local);

  final MessagesMockDataSource _local;

  @override
  List<Conversation> getConversations() => _local.fetchConversations();
}
