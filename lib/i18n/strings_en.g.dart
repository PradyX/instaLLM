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
	late final Translations$profileImages$en profileImages = Translations$profileImages$en._(_root);
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

// Path: profileImages
class Translations$profileImages$en {
	Translations$profileImages$en._(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Profile image'
	String get title => 'Profile image';

	/// en: 'Choose'
	String get choose => 'Choose';

	/// en: 'Choose a Petdex profile image'
	String get pickerTitle => 'Choose a Petdex profile image';

	/// en: 'Search pets by name'
	String get search => 'Search pets by name';

	/// en: 'Search loads images from Petdex. Only selected images and visible search results are cached.'
	String get networkHint => 'Search loads images from Petdex. Only selected images and visible search results are cached.';

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
			'common.error' => 'Error',
			'common.success' => 'Success',
			'common.close' => 'Close',
			'common.ok' => 'OK',
			'common.yes' => 'Yes',
			'common.no' => 'No',
			'profileImages.title' => 'Profile image',
			'profileImages.choose' => 'Choose',
			'profileImages.pickerTitle' => 'Choose a Petdex profile image',
			'profileImages.search' => 'Search pets by name',
			'profileImages.networkHint' => 'Search loads images from Petdex. Only selected images and visible search results are cached.',
			'profileImages.startSearch' => 'Search for a pet to see profile images.',
			'profileImages.noResults' => 'No pets found. Try another name.',
			'profileImages.catalogError' => 'Could not load Petdex. Check your connection and retry.',
			'profileImages.imageError' => 'Could not load this image. Check your connection and try again.',
			'profileImages.saveError' => 'Could not save the profile image. Check available storage and use the latest app version.',
			'profileImages.retry' => 'Retry',
			'profileImages.useDefault' => 'Use default icon',
			_ => null,
		};
	}
}
