import '../models/language_notifier.dart';

/// Staff Portal translation table (English / Hindi / Tamil). Keyed by a
/// stable English key so callers read `st('tab_home')` rather than raw text.
/// Only the Staff Portal (Housekeeping/Support Staff) is translated — every
/// other shell in the app stays English-only.
const Map<String, Map<AppLanguage, String>> _staffStrings = {
  // ── Shell / nav ──────────────────────────────────────────────────────
  'tab_home':        {AppLanguage.en: 'Home',       AppLanguage.hi: 'होम',            AppLanguage.ta: 'முகப்பு'},
  'tab_leave':       {AppLanguage.en: 'Leave',      AppLanguage.hi: 'छुट्टी',          AppLanguage.ta: 'விடுப்பு'},
  'tab_permission':  {AppLanguage.en: 'Permission', AppLanguage.hi: 'अनुमति',          AppLanguage.ta: 'அனுமதி'},
  'tab_profile':     {AppLanguage.en: 'Profile',    AppLanguage.hi: 'प्रोफ़ाइल',       AppLanguage.ta: 'சுயவிவரம்'},
  'logout_tooltip':  {AppLanguage.en: 'Log out',    AppLanguage.hi: 'लॉग आउट',         AppLanguage.ta: 'வெளியேறு'},
  'logout_title':    {AppLanguage.en: 'Log out?',   AppLanguage.hi: 'लॉग आउट करें?',   AppLanguage.ta: 'வெளியேறவா?'},
  'logout_body':     {AppLanguage.en: 'You will need to sign in again to continue.',
                       AppLanguage.hi: 'जारी रखने के लिए आपको फिर से साइन इन करना होगा।',
                       AppLanguage.ta: 'தொடர மீண்டும் உள்நுழைய வேண்டும்.'},
  'cancel':          {AppLanguage.en: 'Cancel',     AppLanguage.hi: 'रद्द करें',       AppLanguage.ta: 'ரத்து செய்'},
  'log_out':         {AppLanguage.en: 'Log Out',    AppLanguage.hi: 'लॉग आउट',         AppLanguage.ta: 'வெளியேறு'},
  'language':        {AppLanguage.en: 'Language',   AppLanguage.hi: 'भाषा',            AppLanguage.ta: 'மொழி'},
  'choose_language': {AppLanguage.en: 'Choose your language',
                       AppLanguage.hi: 'अपनी भाषा चुनें',
                       AppLanguage.ta: 'உங்கள் மொழியைத் தேர்ந்தெடுக்கவும்'},

  // ── Report a problem (every shell) ───────────────────────────────────
  'report_problem':  {AppLanguage.en: 'Report a problem', AppLanguage.hi: 'समस्या बताएं', AppLanguage.ta: 'பிரச்சனையைத் தெரிவி'},
  'report_intro':    {AppLanguage.en: 'Tell us what went wrong. Your name and this screen are sent with it.',
                       AppLanguage.hi: 'बताएं क्या गलत हुआ। आपका नाम और यह स्क्रीन साथ में भेजे जाएंगे।',
                       AppLanguage.ta: 'என்ன தவறு நடந்தது என்று சொல்லுங்கள். உங்கள் பெயரும் இந்தத் திரையும் சேர்த்து அனுப்பப்படும்.'},
  'report_hint':     {AppLanguage.en: 'What were you doing, and what happened?',
                       AppLanguage.hi: 'आप क्या कर रहे थे, और क्या हुआ?',
                       AppLanguage.ta: 'நீங்கள் என்ன செய்து கொண்டிருந்தீர்கள், என்ன நடந்தது?'},
  'report_describe': {AppLanguage.en: 'Please describe the problem.',
                       AppLanguage.hi: 'कृपया समस्या बताएं।',
                       AppLanguage.ta: 'பிரச்சனையை விவரிக்கவும்.'},
  'report_screen':   {AppLanguage.en: 'Screen', AppLanguage.hi: 'स्क्रीन', AppLanguage.ta: 'திரை'},
  'report_attach':   {AppLanguage.en: 'Attach a picture of this screen',
                       AppLanguage.hi: 'इस स्क्रीन की तस्वीर जोड़ें',
                       AppLanguage.ta: 'இந்தத் திரையின் படத்தை இணை'},
  'report_send':     {AppLanguage.en: 'Send', AppLanguage.hi: 'भेजें', AppLanguage.ta: 'அனுப்பு'},
  'report_sent':     {AppLanguage.en: 'Thanks. Your report has been sent to Management.',
                       AppLanguage.hi: 'धन्यवाद। आपकी रिपोर्ट प्रबंधन को भेज दी गई है।',
                       AppLanguage.ta: 'நன்றி. உங்கள் புகார் நிர்வாகத்திற்கு அனுப்பப்பட்டது.'},

  // ── Home ─────────────────────────────────────────────────────────────
  'check_in':               {AppLanguage.en: 'Check In',  AppLanguage.hi: 'चेक इन',       AppLanguage.ta: 'செக் இன்'},
  'check_out':              {AppLanguage.en: 'Check Out', AppLanguage.hi: 'चेक आउट',      AppLanguage.ta: 'செக் அவுட்'},
  'checked_in_success':     {AppLanguage.en: 'Checked In Successfully',
                              AppLanguage.hi: 'सफलतापूर्वक चेक इन किया गया',
                              AppLanguage.ta: 'வெற்றிகரமாக செக் இன் செய்யப்பட்டது'},
  'shift_completed':        {AppLanguage.en: 'Shift Completed Successfully',
                              AppLanguage.hi: 'शिफ्ट सफलतापूर्वक पूरी हुई',
                              AppLanguage.ta: 'ஷிஃப்ட் வெற்றிகரமாக முடிந்தது'},
  'checked_in_at':          {AppLanguage.en: 'Checked in at',  AppLanguage.hi: 'चेक इन समय',   AppLanguage.ta: 'செக் இன் நேரம்'},
  'checked_out_at':         {AppLanguage.en: 'Checked out at', AppLanguage.hi: 'चेक आउट समय',  AppLanguage.ta: 'செக் அவுட் நேரம்'},
  'greeting_morning':       {AppLanguage.en: 'Good Morning',   AppLanguage.hi: 'सुप्रभात',            AppLanguage.ta: 'காலை வணக்கம்'},
  'greeting_afternoon':     {AppLanguage.en: 'Good Afternoon', AppLanguage.hi: 'शुभ दोपहर',           AppLanguage.ta: 'மதிய வணக்கம்'},
  'greeting_evening':       {AppLanguage.en: 'Good Evening',   AppLanguage.hi: 'शुभ संध्या',          AppLanguage.ta: 'மாலை வணக்கம்'},
  'todays_status':          {AppLanguage.en: "Today's Status", AppLanguage.hi: 'आज की स्थिति',        AppLanguage.ta: 'இன்றைய நிலை'},
  'not_checked_in':         {AppLanguage.en: 'Not Checked In', AppLanguage.hi: 'चेक इन नहीं किया',    AppLanguage.ta: 'செக் இன் செய்யவில்லை'},
  'status_checked_in':      {AppLanguage.en: 'Checked In',     AppLanguage.hi: 'चेक इन किया गया',     AppLanguage.ta: 'செக் இன் செய்யப்பட்டது'},
  'status_shift_completed': {AppLanguage.en: 'Shift Completed',AppLanguage.hi: 'शिफ्ट पूरी हुई',      AppLanguage.ta: 'ஷிஃப்ட் முடிந்தது'},
  'working_hours':          {AppLanguage.en: 'Working Hours',  AppLanguage.hi: 'कार्य के घंटे',       AppLanguage.ta: 'பணி நேரம்'},
  'quick_actions':          {AppLanguage.en: 'Quick Actions',  AppLanguage.hi: 'त्वरित कार्रवाइयाँ',  AppLanguage.ta: 'விரைவு செயல்கள்'},

  // ── Leave ────────────────────────────────────────────────────────────
  'apply_leave':            {AppLanguage.en: 'Apply Leave', AppLanguage.hi: 'छुट्टी के लिए आवेदन करें', AppLanguage.ta: 'விடுப்புக்கு விண்ணப்பிக்கவும்'},
  'leave_date':             {AppLanguage.en: 'Leave Date',  AppLanguage.hi: 'छुट्टी की तारीख',           AppLanguage.ta: 'விடுப்பு தேதி'},
  'select_date':            {AppLanguage.en: 'Select date', AppLanguage.hi: 'तारीख चुनें',               AppLanguage.ta: 'தேதியைத் தேர்ந்தெடுக்கவும்'},
  'apply':                  {AppLanguage.en: 'Apply',       AppLanguage.hi: 'आवेदन करें',                 AppLanguage.ta: 'விண்ணப்பிக்கவும்'},
  'select_leave_date_err':  {AppLanguage.en: 'Please select a leave date.',
                              AppLanguage.hi: 'कृपया छुट्टी की तारीख चुनें।',
                              AppLanguage.ta: 'தயவுசெய்து விடுப்பு தேதியைத் தேர்ந்தெடுக்கவும்.'},
  'leave_submitted':        {AppLanguage.en: 'Leave Request Submitted Successfully.',
                              AppLanguage.hi: 'छुट्टी का अनुरोध सफलतापूर्वक भेजा गया।',
                              AppLanguage.ta: 'விடுப்பு கோரிக்கை வெற்றிகரமாக சமர்ப்பிக்கப்பட்டது.'},
  'leave_allowance_note':   {AppLanguage.en: '{used} holidays used this month · resets monthly',
                              AppLanguage.hi: 'इस महीने {used} छुट्टियाँ उपयोग की गईं · हर महीने रीसेट होता है',
                              AppLanguage.ta: 'இந்த மாதம் {used} விடுப்புகள் பயன்படுத்தப்பட்டன · ஒவ்வொரு மாதமும் மீட்டமைக்கப்படும்'},
  'leave_limit_reached':    {AppLanguage.en: 'You have already used your 1 holiday for this month.',
                              AppLanguage.hi: 'आपने इस महीने अपनी 1 छुट्टी का उपयोग कर लिया है।',
                              AppLanguage.ta: 'இந்த மாதத்திற்கான உங்கள் 1 விடுப்பை ஏற்கனவே பயன்படுத்திவிட்டீர்கள்.'},
  'fill_leave_details':     {AppLanguage.en: 'Fill in the details to apply for leave',
                              AppLanguage.hi: 'छुट्टी के लिए विवरण भरें',
                              AppLanguage.ta: 'விடுப்புக்கான விவரங்களை நிரப்பவும்'},
  'leave_type':             {AppLanguage.en: 'Leave Type',       AppLanguage.hi: 'छुट्टी का प्रकार',        AppLanguage.ta: 'விடுப்பு வகை'},
  'select_leave_type':      {AppLanguage.en: 'Select leave type',AppLanguage.hi: 'छुट्टी का प्रकार चुनें', AppLanguage.ta: 'விடுப்பு வகையைத் தேர்ந்தெடுக்கவும்'},
  'leave_type_casual':      {AppLanguage.en: 'Casual Leave',     AppLanguage.hi: 'आकस्मिक छुट्टी',          AppLanguage.ta: 'சாதாரண விடுப்பு'},
  'leave_type_medical':     {AppLanguage.en: 'Medical Leave',    AppLanguage.hi: 'चिकित्सा छुट्टी',         AppLanguage.ta: 'மருத்துவ விடுப்பு'},
  'select_leave_type_err':  {AppLanguage.en: 'Please select a leave type.',
                              AppLanguage.hi: 'कृपया छुट्टी का प्रकार चुनें।',
                              AppLanguage.ta: 'தயவுசெய்து விடுப்பு வகையைத் தேர்ந்தெடுக்கவும்.'},
  'leave_history':          {AppLanguage.en: 'Leave History', AppLanguage.hi: 'छुट्टी का इतिहास', AppLanguage.ta: 'விடுப்பு வரலாறு'},

  // ── Permission ───────────────────────────────────────────────────────
  'apply_permission':       {AppLanguage.en: 'Apply Permission', AppLanguage.hi: 'अनुमति के लिए आवेदन करें', AppLanguage.ta: 'அனுமதிக்கு விண்ணப்பிக்கவும்'},
  'permission_date':        {AppLanguage.en: 'Permission Date',  AppLanguage.hi: 'अनुमति की तारीख',           AppLanguage.ta: 'அனுமதி தேதி'},
  'permission_duration':    {AppLanguage.en: 'Permission Duration', AppLanguage.hi: 'अनुमति की अवधि',        AppLanguage.ta: 'அனுமதி காலம்'},
  'duration_30m':           {AppLanguage.en: '30 Minutes',       AppLanguage.hi: '30 मिनट',                    AppLanguage.ta: '30 நிமிடங்கள்'},
  'duration_1h':            {AppLanguage.en: '1 Hour',           AppLanguage.hi: '1 घंटा',                     AppLanguage.ta: '1 மணி நேரம்'},
  'duration_1h30m':         {AppLanguage.en: '1 Hour 30 Minutes',AppLanguage.hi: '1 घंटा 30 मिनट',             AppLanguage.ta: '1 மணி 30 நிமிடங்கள்'},
  'duration_2h':            {AppLanguage.en: '2 Hours',          AppLanguage.hi: '2 घंटे',                     AppLanguage.ta: '2 மணி நேரம்'},
  'select_permission_date_err': {AppLanguage.en: 'Please select a permission date.',
                              AppLanguage.hi: 'कृपया अनुमति की तारीख चुनें।',
                              AppLanguage.ta: 'தயவுசெய்து அனுமதி தேதியைத் தேர்ந்தெடுக்கவும்.'},
  'permission_submitted':   {AppLanguage.en: 'Permission Request Submitted Successfully.',
                              AppLanguage.hi: 'अनुमति का अनुरोध सफलतापूर्वक भेजा गया।',
                              AppLanguage.ta: 'அனுமதி கோரிக்கை வெற்றிகரமாக சமர்ப்பிக்கப்பட்டது.'},
  'permission_limit_reached': {AppLanguage.en: 'You have already used your maximum 2 permissions for this month.',
                              AppLanguage.hi: 'आपने इस महीने अपनी अधिकतम 2 अनुमतियों का उपयोग कर लिया है।',
                              AppLanguage.ta: 'இந்த மாதத்திற்கான உங்கள் அதிகபட்ச 2 அனுமதிகளை ஏற்கனவே பயன்படுத்திவிட்டீர்கள்.'},
  'fill_permission_details': {AppLanguage.en: 'Fill in the details to apply for permission',
                              AppLanguage.hi: 'अनुमति के लिए विवरण भरें',
                              AppLanguage.ta: 'அனுமதிக்கான விவரங்களை நிரப்பவும்'},
  'permission_history':     {AppLanguage.en: 'Permission History', AppLanguage.hi: 'अनुमति का इतिहास', AppLanguage.ta: 'அனுமதி வரலாறு'},

  // ── History (leave/permission status) ───────────────────────────────
  'history':                {AppLanguage.en: 'History',   AppLanguage.hi: 'इतिहास',        AppLanguage.ta: 'வரலாறு'},
  'status_approved':        {AppLanguage.en: 'Approved',  AppLanguage.hi: 'स्वीकृत',       AppLanguage.ta: 'அங்கீகரிக்கப்பட்டது'},
  'status_denied':          {AppLanguage.en: 'Denied',    AppLanguage.hi: 'अस्वीकृत',      AppLanguage.ta: 'நிராகரிக்கப்பட்டது'},
  'status_pending':         {AppLanguage.en: 'Pending',   AppLanguage.hi: 'लंबित',         AppLanguage.ta: 'நிலுவையில்'},
  'no_leave_history':       {AppLanguage.en: 'No leave requests yet',
                              AppLanguage.hi: 'अभी तक कोई छुट्टी अनुरोध नहीं',
                              AppLanguage.ta: 'இதுவரை விடுப்பு கோரிக்கைகள் இல்லை'},
  'no_permission_history':  {AppLanguage.en: 'No permission requests yet',
                              AppLanguage.hi: 'अभी तक कोई अनुमति अनुरोध नहीं',
                              AppLanguage.ta: 'இதுவரை அனுமதி கோரிக்கைகள் இல்லை'},
  'filter_all':              {AppLanguage.en: 'All', AppLanguage.hi: 'सभी', AppLanguage.ta: 'அனைத்தும்'},

  // ── Profile ──────────────────────────────────────────────────────────
  'employee_id':   {AppLanguage.en: 'Employee ID',   AppLanguage.hi: 'कर्मचारी आईडी',      AppLanguage.ta: 'பணியாளர் அடையாள எண்'},
  'department':    {AppLanguage.en: 'Department',    AppLanguage.hi: 'विभाग',              AppLanguage.ta: 'துறை'},
  'designation':   {AppLanguage.en: 'Designation',   AppLanguage.hi: 'पदनाम',              AppLanguage.ta: 'பதவி'},
  'manager':       {AppLanguage.en: 'Manager',       AppLanguage.hi: 'प्रबंधक',            AppLanguage.ta: 'மேலாளர்'},
  'phone_number':  {AppLanguage.en: 'Phone Number',  AppLanguage.hi: 'फ़ोन नंबर',          AppLanguage.ta: 'தொலைபேசி எண்'},
  'joining_date':  {AppLanguage.en: 'Joining Date',  AppLanguage.hi: 'शामिल होने की तारीख', AppLanguage.ta: 'சேர்ந்த தேதி'},
  'holiday_allowance': {AppLanguage.en: 'Holiday Allowance',
                         AppLanguage.hi: 'छुट्टी भत्ता',
                         AppLanguage.ta: 'விடுப்பு கொடையளவு'},
  'my_profile':    {AppLanguage.en: 'My Profile', AppLanguage.hi: 'मेरी प्रोफ़ाइल', AppLanguage.ta: 'எனது சுயவிவரம்'},
};

/// Looks up [key] in the current staff-portal language; falls back to
/// English, then to the raw key if the entry itself is missing.
String st(String key) {
  final entry = _staffStrings[key];
  if (entry == null) return key;
  return entry[staffLanguageNotifier.value] ?? entry[AppLanguage.en] ?? key;
}

const _languageNames = {
  AppLanguage.en: 'English',
  AppLanguage.hi: 'हिन्दी',
  AppLanguage.ta: 'தமிழ்',
};

/// A language's own display name, always shown in its own script
/// regardless of the currently active language.
String languageDisplayName(AppLanguage lang) => _languageNames[lang]!;
