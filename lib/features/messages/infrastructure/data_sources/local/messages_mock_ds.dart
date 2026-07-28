import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../domain/entities/conversation.dart';

/// Static conversation seed — a 1:1 port of the prototype's `chats` array
/// (design script line 7247). This is the ONLY place chat sample data lives;
/// swap it for a remote source and the UI is unchanged.
class MessagesMockDataSource {
  const MessagesMockDataSource();

  List<Conversation> fetchConversations() => const [
        Conversation(
          id: 'ch1',
          leadId: 'L1001',
          name: 'Ramesh Pillai',
          company: 'Kalyan Silks',
          initials: 'RP',
          online: true,
          unread: 0,
          windowLeft: '20h 58m left',
          lastTime: '10:33 AM',
          messages: [
            ChatMessage(mine: false, text: 'Hi, we reviewed the showroom interior plan — looks great overall.', time: '9:58 AM'),
            ChatMessage(mine: true, text: 'Glad to hear that! Shall I share the revised fit-out quote with the timeline?', time: '10:24 AM', status: 'read'),
            ChatMessage(mine: false, text: 'Yes please, send it along with the 6-week schedule.', time: '10:31 AM'),
            ChatMessage(mine: true, text: 'Sending the quote PDF and the schedule now.', time: '10:33 AM', status: 'read'),
          ],
          media: [
            ChatMedia(icon: PhosphorIconsRegular.filePdf, name: 'Fit-out quote v2.pdf', meta: 'PDF · 1.2 MB · Today'),
            ChatMedia(icon: PhosphorIconsRegular.fileXls, name: 'Site schedule — 6 weeks.xlsx', meta: 'XLSX · 84 KB · Today'),
          ],
          links: [
            ChatLink(title: 'Kairali portfolio — retail showrooms', url: 'kairali.in/work/showrooms', meta: '2d ago'),
          ],
        ),
        Conversation(
          id: 'ch2',
          leadId: 'L1002',
          name: 'Aboobacker Haji',
          company: 'Lulu Fashion Store',
          initials: 'AH',
          online: false,
          unread: 3,
          windowLeft: '18h 40m left',
          lastTime: '9:52 AM',
          messages: [
            ChatMessage(mine: true, text: 'Sharing the revised estimate for the flagship fit-out.', time: 'Yesterday', status: 'read'),
            ChatMessage(mine: false, text: 'Can we relook at the lighting spec for the trial floor?', time: '9:40 AM'),
            ChatMessage(mine: true, text: "Absolutely. I'll revise the lighting spec and share by evening.", time: '9:45 AM', status: 'read'),
            ChatMessage(mine: false, text: 'Great, thank you.', time: '9:50 AM'),
            ChatMessage(mine: false, text: 'Also — the MEP quote needs a small update.', time: '9:51 AM'),
            ChatMessage(mine: false, text: 'Can you call me tomorrow at 10?', time: '9:52 AM'),
          ],
        ),
        Conversation(
          id: 'ch3',
          leadId: 'L1003',
          name: 'Jose Kuriakose',
          company: 'Marari Sands Resort',
          initials: 'JK',
          online: false,
          unread: 0,
          windowLeft: null,
          lastTime: '4:28 PM',
          messages: [
            ChatMessage(mine: false, text: 'Thanks for walking us through the villa interiors today.', time: '4:20 PM'),
            ChatMessage(mine: true, text: "You're welcome! Let me know if you'd like the deck options too.", time: '4:28 PM', status: 'read'),
          ],
        ),
        Conversation(
          id: 'ch4',
          leadId: 'L1004',
          name: 'Nikhil Menon',
          company: 'Taj Gateway Annexe',
          initials: 'NM',
          online: false,
          unread: 1,
          windowLeft: '20h 0m left',
          lastTime: '8:58 AM',
          messages: [
            ChatMessage(mine: true, text: 'Confirming the site visit on Friday for the banquet hall.', time: '8:45 AM', status: 'read'),
            ChatMessage(mine: false, text: 'Noted. Please bring the lounge layout options as well.', time: '8:58 AM'),
          ],
        ),
        Conversation(
          id: 'ch5',
          leadId: 'L1005',
          name: 'Priya Varma',
          company: 'Aster Medcity OPD',
          initials: 'PV',
          online: false,
          unread: 0,
          windowLeft: null,
          lastTime: 'Mon',
          messages: [
            ChatMessage(mine: false, text: 'Thank you for the smooth handover — the OPD looks fantastic.', time: 'Mon'),
            ChatMessage(mine: true, text: 'Glad the team loved it. We are around for any tweaks.', time: 'Mon', status: 'read'),
          ],
        ),
      ];
}
