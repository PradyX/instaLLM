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
	late final Translations$botCreation$en botCreation = Translations$botCreation$en._(_root);
	late final Translations$botManagement$en botManagement = Translations$botManagement$en._(_root);
	late final Translations$roomMentions$en roomMentions = Translations$roomMentions$en._(_root);
	late final Translations$roomManagement$en roomManagement = Translations$roomManagement$en._(_root);
	late final Translations$modelRepository$en modelRepository = Translations$modelRepository$en._(_root);
	late final Translations$roomBoard$en roomBoard = Translations$roomBoard$en._(_root);
	late final Translations$profileImages$en profileImages = Translations$profileImages$en._(_root);
	late final Translations$navigation$en navigation = Translations$navigation$en._(_root);
	late final Translations$appearance$en appearance = Translations$appearance$en._(_root);
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
			'common.error' => 'Error',
			'common.success' => 'Success',
			'common.close' => 'Close',
			'common.ok' => 'OK',
			'common.yes' => 'Yes',
			'common.no' => 'No',
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
			'botManagement.historyOnly' => 'Chat history',
			'botManagement.unavailable' => 'This bot is no longer active. Its chat history is preserved.',
			'botManagement.emptyHistory' => 'No messages in this saved chat.',
			'botManagement.unavailableAssignee' => 'Unavailable bot',
			'roomMentions.title' => 'Mention a room member',
			'roomManagement.settings' => 'Room settings',
			'roomManagement.chatSettings' => 'Chat settings',
			'roomManagement.clear' => 'Clear chat',
			'roomManagement.clearTitle' => 'Clear this chat?',
			'roomManagement.clearHint' => 'This permanently clears its messages. The bot, chat settings and Board tasks are kept.',
			'roomManagement.clearError' => 'Could not clear the chat. Finish any running reply, check available storage and try again.',
			'modelRepository.addError' => 'Could not add this model. Please try again.',
			'roomBoard.linkedTasks' => 'Linked tasks',
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
			_ => null,
		};
	}
}
