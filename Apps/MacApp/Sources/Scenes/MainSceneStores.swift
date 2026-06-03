import BriefFeature
import InboxFeature
import ThreadFeature
import TranslationFeature

extension MainScene {
    var inboxStore: InboxStore { composition.inboxStore }
    var threadStore: ThreadStore { composition.threadStore }
    var briefStore: BriefStore { composition.briefStore }
    var translationStore: TranslationStore { composition.translationStore }
    var aiReady: Bool { composition.aiModelController.isAIReady }
}
