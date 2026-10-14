///
/// Generated file. Do not edit.
///
// coverage:ignore-file
// ignore_for_file: type=lint, unused_import
// dart format off

part of 'strings.g.dart';

// Path: <root>
typedef TranslationsEn = Translations; // ignore: unused_element
class Translations with BaseTranslations<AppLocale, Translations> {
	/// Returns the current translations of the given [context].
	///
	/// Usage:
	/// final t = Translations.of(context);
	static Translations of(BuildContext context) => InheritedLocaleData.of<AppLocale, Translations>(context).translations;

	/// You can call this constructor and build your own translation instance of this locale.
	/// Constructing via the enum [AppLocale.build] is preferred.
	Translations({Map<String, Node>? overrides, PluralResolver? cardinalResolver, PluralResolver? ordinalResolver, TranslationMetadata<AppLocale, Translations>? meta})
		: assert(overrides == null, 'Set "translation_overrides: true" in order to enable this feature.'),
		  _meta = meta ?? TranslationMetadata(
		    locale: AppLocale.en,
		    overrides: overrides ?? {},
		    cardinalResolver: cardinalResolver,
		    ordinalResolver: ordinalResolver,
		  ) {
		_meta.setFlatMapFunction(_flatMapFunction);
	}

	/// Metadata for the translations of <en>.
	final TranslationMetadata<AppLocale, Translations> _meta;
	@override TranslationMetadata<AppLocale, Translations> get $meta => _meta;

	/// Access flat map
	dynamic operator[](String key) => _meta.getTranslation(key);

	late final Translations _root = this; // ignore: unused_field

	Translations $copyWith({TranslationMetadata<AppLocale, Translations>? meta}) => Translations(meta: meta ?? this.$meta);

	// Translations
	late final Translations$login$en login = Translations$login$en._(_root);
	late final Translations$home$en home = Translations$home$en._(_root);
	late final Translations$common$en common = Translations$common$en._(_root);
	late final Translations$memory$en memory = Translations$memory$en._(_root);
	late final Translations$botCreation$en botCreation = Translations$botCreation$en._(_root);
	late final Translations$botManagement$en botManagement = Translations$botManagement$en._(_root);
	late final Translations$roomMentions$en roomMentions = Translations$roomMentions$en._(_root);
	late final Translations$roomManagement$en roomManagement = Translations$roomManagement$en._(_root);
	late final Translations$modelRepository$en modelRepository = Translations$modelRepository$en._(_root);
	late final Translations$roomBoard$en roomBoard = Translations$roomBoard$en._(_root);
	late final Translations$profileImages$en profileImages = Translations$profileImages$en._(_root);
	late final Translations$navigation$en navigation = Translations$navigation$en._(_root);
	late final Translations$appearance$en appearance = Translations$appearance$en._(_root);
	late final Translations$vault$en vault = Translations$vault$en._(_root);
}

// Path: login
class Translations$login$en {
	Translations$login$en._(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Welcome Back'
	String get welcome => 'Welcome Back';

	/// en: 'Sign in to continue'
	String get subtitle => 'Sign in to continue';

	/// en: 'Username'
	String get username => 'Username';

	/// en: 'Password'
	String get password => 'Password';

	/// en: 'Sign In'
	String get signIn => 'Sign In';

	/// en: 'Forgot Password?'
	String get forgotPassword => 'Forgot Password?';

	/// en: 'Login via OTP'
	String get loginOtp => 'Login via OTP';

	/// en: 'Create Account'
	String get createAccount => 'Create Account';

	/// en: 'Don't have an account? '
	String get noAccountLabel => 'Don\'t have an account? ';

	/// en: 'Email or Phone is required'
	String get emailOrPhoneRequired => 'Email or Phone is required';

	/// en: 'Password is required'
	String get passwordRequired => 'Password is required';
}

// Path: home
class Translations$home$en {
	Translations$home$en._(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Home'
	String get title => 'Home';

	/// en: 'Settings'
	String get settings => 'Settings';

	/// en: 'Logout'
	String get logout => 'Logout';
}

// Path: common
class Translations$common$en {
	Translations$common$en._(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Cancel'
	String get cancel => 'Cancel';

	/// en: 'Manage'
	String get manage => 'Manage';

	/// en: 'Error'
	String get error => 'Error';

	/// en: 'Success'
	String get success => 'Success';

	/// en: 'Close'
	String get close => 'Close';

	/// en: 'OK'
	String get ok => 'OK';

	/// en: 'Yes'
	String get yes => 'Yes';

	/// en: 'No'
	String get no => 'No';
}

// Path: memory
class Translations$memory$en {
	Translations$memory$en._(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Memory'
	String get title => 'Memory';

	/// en: 'Facts you choose to remember on this device'
	String get subtitle => 'Facts you choose to remember on this device';

	/// en: 'No saved facts yet.'
	String get empty => 'No saved facts yet.';

	/// en: 'In chat: remember X or forget X. For workspace facts: remember in workspace: X. Global recording requires remember globally: X or the explicit choice below.'
	String get help => 'In chat: remember X or forget X. For workspace facts: remember in workspace: X. Global recording requires remember globally: X or the explicit choice below.';

	/// en: 'Add fact'
	String get add => 'Add fact';

	/// en: 'Edit fact'
	String get edit => 'Edit fact';

	/// en: 'Save'
	String get save => 'Save';

	/// en: 'Delete'
	String get delete => 'Delete';

	/// en: 'Delete this saved fact?'
	String get deleteTitle => 'Delete this saved fact?';

	/// en: 'The fact will be removed from saved memory. Chat messages and conversation summaries are kept.'
	String get deleteHint => 'The fact will be removed from saved memory. Chat messages and conversation summaries are kept.';

	/// en: 'Fact'
	String get fact => 'Fact';

	/// en: 'Scope'
	String get scope => 'Scope';

	/// en: 'Conversation'
	String get conversation => 'Conversation';

	/// en: 'Workspace'
	String get workspace => 'Workspace';

	/// en: 'Global'
	String get global => 'Global';

	/// en: 'Save in'
	String get owner => 'Save in';

	/// en: 'User-stated'
	String get userStated => 'User-stated';

	/// en: 'Inferred'
	String get inferred => 'Inferred';

	/// en: 'Bot-recorded'
	String get botRecorded => 'Bot-recorded';

	/// en: 'Expired'
	String get expired => 'Expired';

	/// en: 'Global recall off'
	String get globalDisabled => 'Global recall off';

	/// en: 'Use this fact across all workspaces'
	String get globalConsent => 'Use this fact across all workspaces';

	/// en: 'This choice applies only to this fact. Bots also need Global memory scope to recall it.'
	String get globalHint => 'This choice applies only to this fact. Bots also need Global memory scope to recall it.';

	/// en: 'Expires on (optional, YYYY-MM-DD)'
	String get expires => 'Expires on (optional, YYYY-MM-DD)';

	/// en: 'Enter a valid date as YYYY-MM-DD.'
	String get dateError => 'Enter a valid date as YYYY-MM-DD.';

	/// en: 'Enter one fact of up to 1000 characters.'
	String get textError => 'Enter one fact of up to 1000 characters.';

	/// en: 'Choose a conversation or workspace.'
	String get ownerError => 'Choose a conversation or workspace.';

	/// en: 'Could not save memory. Check available storage and try again.'
	String get saveError => 'Could not save memory. Check available storage and try again.';

	/// en: 'No exact saved fact matches in this scope. Check Settings → Memory.'
	String get noMatch => 'No exact saved fact matches in this scope. Check Settings → Memory.';

	/// en: 'Several saved facts match. Delete the one you mean in Settings → Memory.'
	String get ambiguous => 'Several saved facts match. Delete the one you mean in Settings → Memory.';

	/// en: 'Saved in memory.'
	String get remembered => 'Saved in memory.';

	/// en: 'Removed from saved memory. Chat history and summaries are kept.'
	String get forgotten => 'Removed from saved memory. Chat history and summaries are kept.';

	/// en: 'Choose global use for this fact before saving it.'
	String get globalRequired => 'Choose global use for this fact before saving it.';

	/// en: 'Choose a workspace before saving a workspace fact.'
	String get workspaceRequired => 'Choose a workspace before saving a workspace fact.';

	/// en: 'Remember a fact, or install a model to chat…'
	String get noModelHint => 'Remember a fact, or install a model to chat…';

	/// en: 'Workspace memory is unavailable. Check Settings → Workspaces.'
	String get noWorkspace => 'Workspace memory is unavailable. Check Settings → Workspaces.';

	/// en: 'Saved scope'
	String get unavailableOwner => 'Saved scope';

	/// en: 'Try again'
	String get retry => 'Try again';

	/// en: 'Chat commands'
	String get commands => 'Chat commands';

	/// en: 'Fact actions'
	String get actions => 'Fact actions';

	/// en: 'Saved memory uses an unsupported format. Update InstaLLM to edit it; the file has been left untouched.'
	String get unsupported => 'Saved memory uses an unsupported format. Update InstaLLM to edit it; the file has been left untouched.';

	/// en: 'Saved memory uses an unsupported format. Update InstaLLM before editing it.'
	String get unsupportedEdit => 'Saved memory uses an unsupported format. Update InstaLLM before editing it.';

	/// en: 'Could not read saved memory. Check access to the app support folder and try again. Local chat remains available.'
	String get readError => 'Could not read saved memory. Check access to the app support folder and try again. Local chat remains available.';

	/// en: 'Could not save memory. Check free space and access to the app support folder, then try again. Existing facts were kept.'
	String get storageError => 'Could not save memory. Check free space and access to the app support folder, then try again. Existing facts were kept.';

	/// en: 'Confirm sharing this fact across all workspaces before saving it.'
	String get consentError => 'Confirm sharing this fact across all workspaces before saving it.';

	/// en: 'Enter one fact of up to 1000 characters and choose its conversation or workspace.'
	String get ownerTextError => 'Enter one fact of up to 1000 characters and choose its conversation or workspace.';

	/// en: 'This memory fact no longer exists.'
	String get missingFact => 'This memory fact no longer exists.';
}

// Path: botCreation
class Translations$botCreation$en {
	Translations$botCreation$en._(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'New bot'
	String get title => 'New bot';

	/// en: 'Name'
	String get name => 'Name';

	/// en: 'Create'
	String get create => 'Create';

	/// en: 'Template'
	String get template => 'Template';

	/// en: 'None'
	String get noTemplate => 'None';

	/// en: 'Optional. Choose a role, then make it your own.'
	String get templateHint => 'Optional. Choose a role, then make it your own.';

	/// en: 'Soul'
	String get soul => 'Soul';

	/// en: 'Describe how your bot should behave and answer.'
	String get soulHint => 'Describe how your bot should behave and answer.';

	/// en: 'You are a helpful assistant. Give clear, practical answers. Ask for clarification when needed.'
	String get starterSoul => 'You are a helpful assistant.\nGive clear, practical answers.\nAsk for clarification when needed.';

	/// en: 'Keep the bot icon or choose a pet.'
	String get defaultPortrait => 'Keep the bot icon or choose a pet.';

	/// en: 'Search pets'
	String get searchPortraits => 'Search pets';

	/// en: 'Only confirmed portraits are saved for offline use.'
	String get portraitHint => 'Only confirmed portraits are saved for offline use.';

	/// en: 'Portraits are unavailable. You can still create your bot.'
	String get portraitsOffline => 'Portraits are unavailable. You can still create your bot.';

	/// en: 'Previous portraits'
	String get previousPortraits => 'Previous portraits';

	/// en: 'Next portraits'
	String get nextPortraits => 'Next portraits';

	/// en: 'Bot saved. Tap it in Bots to open its chat again.'
	String get chatError => 'Bot saved. Tap it in Bots to open its chat again.';

	/// en: 'No bots yet. Use + to create your own.'
	String get empty => 'No bots yet. Use + to create your own.';

	/// en: 'Could not create the bot. Check available storage and try again.'
	String get saveError => 'Could not create the bot. Check available storage and try again.';
}

// Path: botManagement
class Translations$botManagement$en {
	Translations$botManagement$en._(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Bot settings'
	String get settings => 'Bot settings';

	/// en: 'Edit bot'
	String get edit => 'Edit bot';

	/// en: 'Delete bot'
	String get delete => 'Delete bot';

	/// en: 'Delete this bot?'
	String get deleteTitle => 'Delete this bot?';

	/// en: 'The bot will be removed from your list. Its chats and messages stay readable in Rooms.'
	String get deleteHint => 'The bot will be removed from your list. Its chats and messages stay readable in Rooms.';

	/// en: 'Could not delete the bot. Check available storage and try again.'
	String get deleteError => 'Could not delete the bot. Check available storage and try again.';

	/// en: 'Your chat history is kept.'
	String get deleteSummary => 'Your chat history is kept.';

	/// en: 'Chat history'
	String get historyOnly => 'Chat history';

	/// en: 'This bot is no longer active. Its chat history is preserved.'
	String get unavailable => 'This bot is no longer active. Its chat history is preserved.';

	/// en: 'No messages in this saved chat.'
	String get emptyHistory => 'No messages in this saved chat.';

	/// en: 'Unavailable bot'
	String get unavailableAssignee => 'Unavailable bot';
}

// Path: roomMentions
class Translations$roomMentions$en {
	Translations$roomMentions$en._(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Mention a room member'
	String get title => 'Mention a room member';
}

// Path: roomManagement
class Translations$roomManagement$en {
	Translations$roomManagement$en._(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Room settings'
	String get settings => 'Room settings';

	/// en: 'Chat settings'
	String get chatSettings => 'Chat settings';

	/// en: 'Clear chat'
	String get clear => 'Clear chat';

	/// en: 'Remove messages. Keep this bot.'
	String get clearSummary => 'Remove messages. Keep this bot.';

	/// en: 'Remove messages. Keep this chat.'
	String get clearSavedSummary => 'Remove messages. Keep this chat.';

	/// en: 'Clear this chat?'
	String get clearTitle => 'Clear this chat?';

	/// en: 'This permanently clears its messages. The bot, chat settings and Board tasks are kept.'
	String get clearHint => 'This permanently clears its messages. The bot, chat settings and Board tasks are kept.';

	/// en: 'Could not clear the chat. Finish any running reply, check available storage and try again.'
	String get clearError => 'Could not clear the chat. Finish any running reply, check available storage and try again.';
}

// Path: modelRepository
class Translations$modelRepository$en {
	Translations$modelRepository$en._(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Could not add this model. Please try again.'
	String get addError => 'Could not add this model. Please try again.';
}

// Path: roomBoard
class Translations$roomBoard$en {
	Translations$roomBoard$en._(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Linked tasks'
	String get linkedTasks => 'Linked tasks';

	/// en: 'No linked tasks yet.'
	String get emptyLinkedTasks => 'No linked tasks yet.';

	/// en: 'Linked rooms'
	String get linkedRooms => 'Linked rooms';

	/// en: 'Link task'
	String get linkTask => 'Link task';

	/// en: 'Open board'
	String get openBoard => 'Open board';

	/// en: 'Change task status'
	String get changeStatus => 'Change task status';

	/// en: 'No unlinked tasks in this workspace. Create one on the Board or from a room message.'
	String get noTasks => 'No unlinked tasks in this workspace. Create one on the Board or from a room message.';

	/// en: 'Could not load linked tasks.'
	String get loadError => 'Could not load linked tasks.';

	/// en: 'Could not save the task change'
	String get saveError => 'Could not save the task change';

	/// en: 'Could not open a room for the task'
	String get openError => 'Could not open a room for the task';

	/// en: 'Discuss in room'
	String get discuss => 'Discuss in room';

	/// en: 'Open room'
	String get openRoom => 'Open room';
}

// Path: profileImages
class Translations$profileImages$en {
	Translations$profileImages$en._(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Browse'
	String get browse => 'Browse';

	/// en: 'Saved'
	String get saved => 'Saved';

	/// en: 'No saved portraits yet.'
	String get noSaved => 'No saved portraits yet.';

	/// en: 'Profile image'
	String get title => 'Profile image';

	/// en: 'Choose'
	String get choose => 'Choose';

	/// en: 'Change image'
	String get change => 'Change image';

	/// en: 'Choose a Petdex profile image'
	String get pickerTitle => 'Choose a Petdex profile image';

	/// en: 'Search pets by name'
	String get search => 'Search pets by name';

	/// en: 'Browse Petdex online. Confirmed portraits are saved for offline use.'
	String get networkHint => 'Browse Petdex online. Confirmed portraits are saved for offline use.';

	/// en: 'Search for a pet to see profile images.'
	String get startSearch => 'Search for a pet to see profile images.';

	/// en: 'No pets found. Try another name.'
	String get noResults => 'No pets found. Try another name.';

	/// en: 'Could not load Petdex. Check your connection and retry.'
	String get catalogError => 'Could not load Petdex. Check your connection and retry.';

	/// en: 'Could not load this image. Check your connection and try again.'
	String get imageError => 'Could not load this image. Check your connection and try again.';

	/// en: 'Could not save the profile image. Check available storage and use the latest app version.'
	String get saveError => 'Could not save the profile image. Check available storage and use the latest app version.';

	/// en: 'Retry'
	String get retry => 'Retry';

	/// en: 'Use default icon'
	String get useDefault => 'Use default icon';
}

// Path: navigation
class Translations$navigation$en {
	Translations$navigation$en._(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Benchmark'
	String get benchmark => 'Benchmark';

	/// en: 'About'
	String get about => 'About';

	/// en: 'Models'
	String get models => 'Models';

	/// en: 'Settings'
	String get settings => 'Settings';

	/// en: 'Chats'
	String get chats => 'Chats';

	/// en: 'Bots'
	String get bots => 'Bots';

	/// en: 'Rooms'
	String get rooms => 'Rooms';

	/// en: 'Switch workspace'
	String get switchWorkspace => 'Switch workspace';

	/// en: 'Manage workspaces'
	String get manageWorkspaces => 'Manage workspaces';

	/// en: 'No workspace'
	String get noWorkspace => 'No workspace';

	/// en: 'Search chats'
	String get searchChats => 'Search chats';

	/// en: 'See all'
	String get seeAll => 'See all';
}

// Path: appearance
class Translations$appearance$en {
	Translations$appearance$en._(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Theme mode'
	String get themeMode => 'Theme mode';

	/// en: 'Auto'
	String get auto => 'Auto';

	/// en: 'Light'
	String get light => 'Light';

	/// en: 'Dark'
	String get dark => 'Dark';

	/// en: 'Surface style'
	String get surfaceStyle => 'Surface style';

	/// en: 'Solid'
	String get solid => 'Solid';

	/// en: 'Translucent'
	String get translucent => 'Translucent';

	/// en: 'Accent colour'
	String get accentColor => 'Accent colour';

	/// en: 'Interface'
	String get interface => 'Interface';

	/// en: 'Contrast'
	String get contrast => 'Contrast';

	/// en: 'Increase the contrast of colours, text and borders.'
	String get contrastHint => 'Increase the contrast of colours, text and borders.';

	/// en: 'Glass opacity'
	String get glassOpacity => 'Glass opacity';

	/// en: 'Higher values make translucent panels more solid.'
	String get glassOpacityHint => 'Higher values make translucent panels more solid.';

	/// en: 'Choose Translucent to adjust glass opacity.'
	String get glassOpacitySolidHint => 'Choose Translucent to adjust glass opacity.';

	/// en: 'Green'
	String get green => 'Green';

	/// en: 'Blue'
	String get blue => 'Blue';

	/// en: 'Purple'
	String get purple => 'Purple';

	/// en: 'Teal'
	String get teal => 'Teal';

	/// en: 'Pink'
	String get pink => 'Pink';

	/// en: 'Orange'
	String get orange => 'Orange';

	/// en: 'Red'
	String get red => 'Red';

	/// en: 'Amber'
	String get amber => 'Amber';

	/// en: 'Grey'
	String get grey => 'Grey';

	/// en: 'Could not save the theme mode. Check available storage and try again.'
	String get modeSaveError => 'Could not save the theme mode. Check available storage and try again.';

	/// en: 'Could not load appearance preferences. Try restarting the app.'
	String get loadError => 'Could not load appearance preferences. Try restarting the app.';

	/// en: 'Could not save appearance preferences. Check available storage and try again.'
	String get saveError => 'Could not save appearance preferences. Check available storage and try again.';

	/// en: 'These appearance preferences need a newer app version. Update the app to change them.'
	String get newerVersion => 'These appearance preferences need a newer app version. Update the app to change them.';
}

// Path: vault
class Translations$vault$en {
	Translations$vault$en._(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Vault'
	String get title => 'Vault';

	/// en: 'Manage vaults'
	String get manage => 'Manage vaults';

	/// en: 'Local Markdown notes and bot journals'
	String get description => 'Local Markdown notes and bot journals';

	/// en: 'Menu'
	String get menu => 'Menu';

	/// en: 'Refresh'
	String get refresh => 'Refresh';

	/// en: 'Find a note by name'
	String get search => 'Find a note by name';

	/// en: 'Select a note to read it.'
	String get selectNote => 'Select a note to read it.';

	/// en: 'No Markdown notes in this folder.'
	String get emptyFolder => 'No Markdown notes in this folder.';

	/// en: 'Choose a vault to browse its notes.'
	String get emptyVault => 'Choose a vault to browse its notes.';

	/// en: 'No matching notes.'
	String get noResults => 'No matching notes.';

	/// en: 'Showing a limited list. Search more specifically or open a smaller folder.'
	String get limit => 'Showing a limited list. Search more specifically or open a smaller folder.';

	/// en: 'Edit'
	String get edit => 'Edit';

	/// en: 'Save'
	String get save => 'Save';

	/// en: 'Cancel'
	String get cancel => 'Cancel';

	/// en: 'Delete'
	String get delete => 'Delete';

	/// en: 'Delete note?'
	String get deleteTitle => 'Delete note?';

	/// en: 'Delete ${name} from this vault? Other notes, chats and bots are kept.'
	String deleteDescription({required Object name}) => 'Delete ${name} from this vault? Other notes, chats and bots are kept.';

	/// en: 'Note saved.'
	String get saved => 'Note saved.';

	/// en: 'Note deleted.'
	String get deleted => 'Note deleted.';

	/// en: 'Back to files'
	String get backToFiles => 'Back to files';

	/// en: 'Discard changes?'
	String get discardTitle => 'Discard changes?';

	/// en: 'Your unsaved edits will be discarded. The file on disk is kept.'
	String get discardDescription => 'Your unsaved edits will be discarded. The file on disk is kept.';

	/// en: 'Discard'
	String get discard => 'Discard';

	/// en: 'This note changed on disk. Your draft is kept. Copy your edits or reload the note before saving or deleting.'
	String get conflict => 'This note changed on disk. Your draft is kept. Copy your edits or reload the note before saving or deleting.';

	/// en: 'Could not read this folder or note. Check folder access and refresh, or choose the folder again in Manage vaults.'
	String get unavailable => 'Could not read this folder or note. Check folder access and refresh, or choose the folder again in Manage vaults.';

	/// en: 'This folder or note no longer exists. Refresh the vault.'
	String get missing => 'This folder or note no longer exists. Refresh the vault.';

	/// en: 'The vault registration changed or access is unavailable. Choose a vault again.'
	String get denied => 'The vault registration changed or access is unavailable. Choose a vault again.';

	/// en: 'Linked or outside folders cannot be accessed here. Choose the original folder instead.'
	String get unsafePath => 'Linked or outside folders cannot be accessed here. Choose the original folder instead.';

	/// en: 'This note exceeds the 512 KB editor limit. Edit it outside the app; its contents are kept.'
	String get tooLarge => 'This note exceeds the 512 KB editor limit. Edit it outside the app; its contents are kept.';

	/// en: 'Image: ${label}'
	String image({required Object label}) => 'Image: ${label}';

	/// en: '${count} vaults'
	String registeredCount({required Object count}) => '${count} vaults';

	/// en: 'Register folder'
	String get register => 'Register folder';

	/// en: 'Prepare managed vault'
	String get prepare => 'Prepare managed vault';

	/// en: 'Managed'
	String get managed => 'Managed';

	/// en: 'External folder'
	String get external => 'External folder';

	/// en: 'Rename'
	String get rename => 'Rename';

	/// en: 'Rename vault'
	String get renameTitle => 'Rename vault';

	/// en: 'Name'
	String get name => 'Name';

	/// en: 'Remove registration'
	String get remove => 'Remove registration';

	/// en: 'Remove vault registration?'
	String get removeTitle => 'Remove vault registration?';

	/// en: 'Remove ${name} and its workspace links from the app? All files in its folder are kept.'
	String removeDescription({required Object name}) => 'Remove ${name} and its workspace links from the app? All files in its folder are kept.';

	/// en: 'Link'
	String get link => 'Link';

	/// en: 'Unlink'
	String get unlink => 'Unlink';

	/// en: 'Link workspace folder'
	String get linkTitle => 'Link workspace folder';

	/// en: 'Folder inside the vault'
	String get folder => 'Folder inside the vault';

	/// en: 'Not linked'
	String get notLinked => 'Not linked';

	/// en: 'No vaults registered yet.'
	String get noVaults => 'No vaults registered yet.';

	/// en: 'Could not save the vault registry. Your previous records are kept.'
	String get registryError => 'Could not save the vault registry. Your previous records are kept.';

	/// en: 'Could not link this folder. Check its path and permissions.'
	String get linkError => 'Could not link this folder. Check its path and permissions.';

	/// en: 'Workspace linked.'
	String get linked => 'Workspace linked.';

	/// en: 'Registered ${name}.'
	String registered({required Object name}) => 'Registered ${name}.';

	/// en: 'Vault renamed.'
	String get renamed => 'Vault renamed.';

	/// en: 'Registration removed. Files are kept.'
	String get removed => 'Registration removed. Files are kept.';

	/// en: 'Vault registry'
	String get backupTitle => 'Vault registry';

	/// en: 'Folder registrations, external folder paths and workspace links; Markdown files stay in their folders'
	String get backupDescription => 'Folder registrations, external folder paths and workspace links; Markdown files stay in their folders';

	/// en: '${count} Vault registration(s) restored'
	String restored({required Object count}) => '${count} Vault registration(s) restored';
}

/// The flat map containing all translations for locale <en>.
/// Only for edge cases! For simple maps, use the map function of this library.
///
/// The Dart AOT compiler has issues with very large switch statements,
/// so the map is split into smaller functions (512 entries each).
extension on Translations {
	dynamic _flatMapFunction(String path) {
		return switch (path) {
			'login.welcome' => 'Welcome Back',
			'login.subtitle' => 'Sign in to continue',
			'login.username' => 'Username',
			'login.password' => 'Password',
			'login.signIn' => 'Sign In',
			'login.forgotPassword' => 'Forgot Password?',
			'login.loginOtp' => 'Login via OTP',
			'login.createAccount' => 'Create Account',
			'login.noAccountLabel' => 'Don\'t have an account? ',
			'login.emailOrPhoneRequired' => 'Email or Phone is required',
			'login.passwordRequired' => 'Password is required',
			'home.title' => 'Home',
			'home.settings' => 'Settings',
			'home.logout' => 'Logout',
			'common.cancel' => 'Cancel',
			'common.manage' => 'Manage',
			'common.error' => 'Error',
			'common.success' => 'Success',
			'common.close' => 'Close',
			'common.ok' => 'OK',
			'common.yes' => 'Yes',
			'common.no' => 'No',
			'memory.title' => 'Memory',
			'memory.subtitle' => 'Facts you choose to remember on this device',
			'memory.empty' => 'No saved facts yet.',
			'memory.help' => 'In chat: remember X or forget X. For workspace facts: remember in workspace: X. Global recording requires remember globally: X or the explicit choice below.',
			'memory.add' => 'Add fact',
			'memory.edit' => 'Edit fact',
			'memory.save' => 'Save',
			'memory.delete' => 'Delete',
			'memory.deleteTitle' => 'Delete this saved fact?',
			'memory.deleteHint' => 'The fact will be removed from saved memory. Chat messages and conversation summaries are kept.',
			'memory.fact' => 'Fact',
			'memory.scope' => 'Scope',
			'memory.conversation' => 'Conversation',
			'memory.workspace' => 'Workspace',
			'memory.global' => 'Global',
			'memory.owner' => 'Save in',
			'memory.userStated' => 'User-stated',
			'memory.inferred' => 'Inferred',
			'memory.botRecorded' => 'Bot-recorded',
			'memory.expired' => 'Expired',
			'memory.globalDisabled' => 'Global recall off',
			'memory.globalConsent' => 'Use this fact across all workspaces',
			'memory.globalHint' => 'This choice applies only to this fact. Bots also need Global memory scope to recall it.',
			'memory.expires' => 'Expires on (optional, YYYY-MM-DD)',
			'memory.dateError' => 'Enter a valid date as YYYY-MM-DD.',
			'memory.textError' => 'Enter one fact of up to 1000 characters.',
			'memory.ownerError' => 'Choose a conversation or workspace.',
			'memory.saveError' => 'Could not save memory. Check available storage and try again.',
			'memory.noMatch' => 'No exact saved fact matches in this scope. Check Settings → Memory.',
			'memory.ambiguous' => 'Several saved facts match. Delete the one you mean in Settings → Memory.',
			'memory.remembered' => 'Saved in memory.',
			'memory.forgotten' => 'Removed from saved memory. Chat history and summaries are kept.',
			'memory.globalRequired' => 'Choose global use for this fact before saving it.',
			'memory.workspaceRequired' => 'Choose a workspace before saving a workspace fact.',
			'memory.noModelHint' => 'Remember a fact, or install a model to chat…',
			'memory.noWorkspace' => 'Workspace memory is unavailable. Check Settings → Workspaces.',
			'memory.unavailableOwner' => 'Saved scope',
			'memory.retry' => 'Try again',
			'memory.commands' => 'Chat commands',
			'memory.actions' => 'Fact actions',
			'memory.unsupported' => 'Saved memory uses an unsupported format. Update InstaLLM to edit it; the file has been left untouched.',
			'memory.unsupportedEdit' => 'Saved memory uses an unsupported format. Update InstaLLM before editing it.',
			'memory.readError' => 'Could not read saved memory. Check access to the app support folder and try again. Local chat remains available.',
			'memory.storageError' => 'Could not save memory. Check free space and access to the app support folder, then try again. Existing facts were kept.',
			'memory.consentError' => 'Confirm sharing this fact across all workspaces before saving it.',
			'memory.ownerTextError' => 'Enter one fact of up to 1000 characters and choose its conversation or workspace.',
			'memory.missingFact' => 'This memory fact no longer exists.',
			'botCreation.title' => 'New bot',
			'botCreation.name' => 'Name',
			'botCreation.create' => 'Create',
			'botCreation.template' => 'Template',
			'botCreation.noTemplate' => 'None',
			'botCreation.templateHint' => 'Optional. Choose a role, then make it your own.',
			'botCreation.soul' => 'Soul',
			'botCreation.soulHint' => 'Describe how your bot should behave and answer.',
			'botCreation.starterSoul' => 'You are a helpful assistant.\nGive clear, practical answers.\nAsk for clarification when needed.',
			'botCreation.defaultPortrait' => 'Keep the bot icon or choose a pet.',
			'botCreation.searchPortraits' => 'Search pets',
			'botCreation.portraitHint' => 'Only confirmed portraits are saved for offline use.',
			'botCreation.portraitsOffline' => 'Portraits are unavailable. You can still create your bot.',
			'botCreation.previousPortraits' => 'Previous portraits',
			'botCreation.nextPortraits' => 'Next portraits',
			'botCreation.chatError' => 'Bot saved. Tap it in Bots to open its chat again.',
			'botCreation.empty' => 'No bots yet. Use + to create your own.',
			'botCreation.saveError' => 'Could not create the bot. Check available storage and try again.',
			'botManagement.settings' => 'Bot settings',
			'botManagement.edit' => 'Edit bot',
			'botManagement.delete' => 'Delete bot',
			'botManagement.deleteTitle' => 'Delete this bot?',
			'botManagement.deleteHint' => 'The bot will be removed from your list. Its chats and messages stay readable in Rooms.',
			'botManagement.deleteError' => 'Could not delete the bot. Check available storage and try again.',
			'botManagement.deleteSummary' => 'Your chat history is kept.',
			'botManagement.historyOnly' => 'Chat history',
			'botManagement.unavailable' => 'This bot is no longer active. Its chat history is preserved.',
			'botManagement.emptyHistory' => 'No messages in this saved chat.',
			'botManagement.unavailableAssignee' => 'Unavailable bot',
			'roomMentions.title' => 'Mention a room member',
			'roomManagement.settings' => 'Room settings',
			'roomManagement.chatSettings' => 'Chat settings',
			'roomManagement.clear' => 'Clear chat',
			'roomManagement.clearSummary' => 'Remove messages. Keep this bot.',
			'roomManagement.clearSavedSummary' => 'Remove messages. Keep this chat.',
			'roomManagement.clearTitle' => 'Clear this chat?',
			'roomManagement.clearHint' => 'This permanently clears its messages. The bot, chat settings and Board tasks are kept.',
			'roomManagement.clearError' => 'Could not clear the chat. Finish any running reply, check available storage and try again.',
			'modelRepository.addError' => 'Could not add this model. Please try again.',
			'roomBoard.linkedTasks' => 'Linked tasks',
			'roomBoard.emptyLinkedTasks' => 'No linked tasks yet.',
			'roomBoard.linkedRooms' => 'Linked rooms',
			'roomBoard.linkTask' => 'Link task',
			'roomBoard.openBoard' => 'Open board',
			'roomBoard.changeStatus' => 'Change task status',
			'roomBoard.noTasks' => 'No unlinked tasks in this workspace. Create one on the Board or from a room message.',
			'roomBoard.loadError' => 'Could not load linked tasks.',
			'roomBoard.saveError' => 'Could not save the task change',
			'roomBoard.openError' => 'Could not open a room for the task',
			'roomBoard.discuss' => 'Discuss in room',
			'roomBoard.openRoom' => 'Open room',
			'profileImages.browse' => 'Browse',
			'profileImages.saved' => 'Saved',
			'profileImages.noSaved' => 'No saved portraits yet.',
			'profileImages.title' => 'Profile image',
			'profileImages.choose' => 'Choose',
			'profileImages.change' => 'Change image',
			'profileImages.pickerTitle' => 'Choose a Petdex profile image',
			'profileImages.search' => 'Search pets by name',
			'profileImages.networkHint' => 'Browse Petdex online. Confirmed portraits are saved for offline use.',
			'profileImages.startSearch' => 'Search for a pet to see profile images.',
			'profileImages.noResults' => 'No pets found. Try another name.',
			'profileImages.catalogError' => 'Could not load Petdex. Check your connection and retry.',
			'profileImages.imageError' => 'Could not load this image. Check your connection and try again.',
			'profileImages.saveError' => 'Could not save the profile image. Check available storage and use the latest app version.',
			'profileImages.retry' => 'Retry',
			'profileImages.useDefault' => 'Use default icon',
			'navigation.benchmark' => 'Benchmark',
			'navigation.about' => 'About',
			'navigation.models' => 'Models',
			'navigation.settings' => 'Settings',
			'navigation.chats' => 'Chats',
			'navigation.bots' => 'Bots',
			'navigation.rooms' => 'Rooms',
			'navigation.switchWorkspace' => 'Switch workspace',
			'navigation.manageWorkspaces' => 'Manage workspaces',
			'navigation.noWorkspace' => 'No workspace',
			'navigation.searchChats' => 'Search chats',
			'navigation.seeAll' => 'See all',
			'appearance.themeMode' => 'Theme mode',
			'appearance.auto' => 'Auto',
			'appearance.light' => 'Light',
			'appearance.dark' => 'Dark',
			'appearance.surfaceStyle' => 'Surface style',
			'appearance.solid' => 'Solid',
			'appearance.translucent' => 'Translucent',
			'appearance.accentColor' => 'Accent colour',
			'appearance.interface' => 'Interface',
			'appearance.contrast' => 'Contrast',
			'appearance.contrastHint' => 'Increase the contrast of colours, text and borders.',
			'appearance.glassOpacity' => 'Glass opacity',
			'appearance.glassOpacityHint' => 'Higher values make translucent panels more solid.',
			'appearance.glassOpacitySolidHint' => 'Choose Translucent to adjust glass opacity.',
			'appearance.green' => 'Green',
			'appearance.blue' => 'Blue',
			'appearance.purple' => 'Purple',
			'appearance.teal' => 'Teal',
			'appearance.pink' => 'Pink',
			'appearance.orange' => 'Orange',
			'appearance.red' => 'Red',
			'appearance.amber' => 'Amber',
			'appearance.grey' => 'Grey',
			'appearance.modeSaveError' => 'Could not save the theme mode. Check available storage and try again.',
			'appearance.loadError' => 'Could not load appearance preferences. Try restarting the app.',
			'appearance.saveError' => 'Could not save appearance preferences. Check available storage and try again.',
			'appearance.newerVersion' => 'These appearance preferences need a newer app version. Update the app to change them.',
			'vault.title' => 'Vault',
			'vault.manage' => 'Manage vaults',
			'vault.description' => 'Local Markdown notes and bot journals',
			'vault.menu' => 'Menu',
			'vault.refresh' => 'Refresh',
			'vault.search' => 'Find a note by name',
			'vault.selectNote' => 'Select a note to read it.',
			'vault.emptyFolder' => 'No Markdown notes in this folder.',
			'vault.emptyVault' => 'Choose a vault to browse its notes.',
			'vault.noResults' => 'No matching notes.',
			'vault.limit' => 'Showing a limited list. Search more specifically or open a smaller folder.',
			'vault.edit' => 'Edit',
			'vault.save' => 'Save',
			'vault.cancel' => 'Cancel',
			'vault.delete' => 'Delete',
			'vault.deleteTitle' => 'Delete note?',
			'vault.deleteDescription' => ({required Object name}) => 'Delete ${name} from this vault? Other notes, chats and bots are kept.',
			'vault.saved' => 'Note saved.',
			'vault.deleted' => 'Note deleted.',
			'vault.backToFiles' => 'Back to files',
			'vault.discardTitle' => 'Discard changes?',
			'vault.discardDescription' => 'Your unsaved edits will be discarded. The file on disk is kept.',
			'vault.discard' => 'Discard',
			'vault.conflict' => 'This note changed on disk. Your draft is kept. Copy your edits or reload the note before saving or deleting.',
			'vault.unavailable' => 'Could not read this folder or note. Check folder access and refresh, or choose the folder again in Manage vaults.',
			'vault.missing' => 'This folder or note no longer exists. Refresh the vault.',
			'vault.denied' => 'The vault registration changed or access is unavailable. Choose a vault again.',
			'vault.unsafePath' => 'Linked or outside folders cannot be accessed here. Choose the original folder instead.',
			'vault.tooLarge' => 'This note exceeds the 512 KB editor limit. Edit it outside the app; its contents are kept.',
			'vault.image' => ({required Object label}) => 'Image: ${label}',
			'vault.registeredCount' => ({required Object count}) => '${count} vaults',
			'vault.register' => 'Register folder',
			'vault.prepare' => 'Prepare managed vault',
			'vault.managed' => 'Managed',
			'vault.external' => 'External folder',
			'vault.rename' => 'Rename',
			'vault.renameTitle' => 'Rename vault',
			'vault.name' => 'Name',
			'vault.remove' => 'Remove registration',
			'vault.removeTitle' => 'Remove vault registration?',
			'vault.removeDescription' => ({required Object name}) => 'Remove ${name} and its workspace links from the app? All files in its folder are kept.',
			'vault.link' => 'Link',
			'vault.unlink' => 'Unlink',
			'vault.linkTitle' => 'Link workspace folder',
			'vault.folder' => 'Folder inside the vault',
			'vault.notLinked' => 'Not linked',
			'vault.noVaults' => 'No vaults registered yet.',
			'vault.registryError' => 'Could not save the vault registry. Your previous records are kept.',
			'vault.linkError' => 'Could not link this folder. Check its path and permissions.',
			'vault.linked' => 'Workspace linked.',
			'vault.registered' => ({required Object name}) => 'Registered ${name}.',
			'vault.renamed' => 'Vault renamed.',
			'vault.removed' => 'Registration removed. Files are kept.',
			'vault.backupTitle' => 'Vault registry',
			'vault.backupDescription' => 'Folder registrations, external folder paths and workspace links; Markdown files stay in their folders',
			'vault.restored' => ({required Object count}) => '${count} Vault registration(s) restored',
			_ => null,
		};
	}
}
