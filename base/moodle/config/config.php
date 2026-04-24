<?php
unset($CFG);
global $CFG;
$CFG = new stdClass();

$CFG->dbtype    = 'mariadb';
$CFG->dblibrary = 'native';
$CFG->dbhost    = getenv('MOODLE_DB_HOST') ?: 'moodle-mariadb';
$CFG->dbname    = 'moodle';
$CFG->dbuser    = 'moodle';
$CFG->dbpass    = getenv('MOODLE_DB_PASS');
$CFG->prefix    = 'mdl_';
$CFG->dboptions = array (
  'dbpersist' => 0,
  'dbport' => '',
  'dbsocket' => '',
  'dbcollation' => 'utf8mb4_unicode_ci',
);

// wwwroot resolution (read top-down):
//
//   1. MOODLE_WWWROOT env var if set to a non-empty absolute URL.
//      Overlays set this per-env to the canonical public URL
//      (e.g. https://school-test-moodle.cybe.tech). Using it as
//      the primary source pins Moodle's generated links — the
//      alternative (inferring from HTTP_HOST) creates redirect
//      loops when the inferred scheme disagrees with the
//      ingress's TLS decision.
//
//   2. Derived from HTTP_HOST + scheme detection. Fallback when
//      MOODLE_WWWROOT is empty (local dev without the overlay).
//
//   3. http://moodle.local as a last-resort default so CLI tools
//      have a wwwroot to echo in error messages.
$_moodle_wwwroot = trim(getenv('MOODLE_WWWROOT') ?: '');
if ($_moodle_wwwroot !== '') {
    $CFG->wwwroot = $_moodle_wwwroot;
} else if (isset($_SERVER['HTTP_HOST'])) {
    $protocol = 'http';
    if (
        (isset($_SERVER['HTTPS']) && $_SERVER['HTTPS'] === 'on') ||
        (isset($_SERVER['HTTP_X_FORWARDED_PROTO']) && $_SERVER['HTTP_X_FORWARDED_PROTO'] === 'https')
    ) {
        $protocol = 'https';
    }
    $CFG->wwwroot = $protocol . '://' . $_SERVER['HTTP_HOST'];
} else {
    $CFG->wwwroot = 'http://moodle.local';
}

// sslproxy: tells Moodle to trust that the request is HTTPS even
// though Apache inside the pod receives plain HTTP from Traefik
// (TLS terminates at the ingress). Without this, Moodle sees
// scheme=http but wwwroot=https, then emits a redirect to
// canonicalize — which Traefik sends back on HTTPS — which Moodle
// still sees as http → infinite loop. Only enable when the
// canonical wwwroot is https://.
if (strpos($CFG->wwwroot, 'https://') === 0) {
    $CFG->sslproxy = true;
}

$CFG->dataroot  = '/var/moodledata';
$CFG->admin     = 'admin';
$CFG->directorypermissions = 0777;

// ------------------------------------------------------------------
//  TWSI brand override
// ------------------------------------------------------------------
//
//  Uses Moodle's `forced_plugin_settings` to inject the theme +
//  presentation config at every request — no DB writes, no admin
//  UI step, no drift between environments. Admin UI renders these
//  fields greyed-out with a "locked by config.php" note, which is
//  the signal we want: branding is infrastructure, not content.
//
//  Two follow-on pieces required for a full rebrand:
//    1. Site course name (`mdl_course.fullname` / `shortname`) —
//       written once by the brand-init Job (base/moodle/brand-init.yaml).
//    2. Theme SCSS cache — the same Job calls purge_all_caches()
//       so the new scsspre/scsspost recompile on next page load.
//
//  When the official SVG brandmark arrives, bake it into the image
//  at /var/www/html/theme/boost/pix/twsi-logo.svg and wire the
//  `logo` plugin setting below.
// ------------------------------------------------------------------
$CFG->theme = 'boost';

$twsi_scss_pre = <<<'SCSS'
// Montserrat — TWSI body/heading face per brand guidelines.
// Cinzel is NOT loaded here: it's reserved for the logo wordmark
// only, rendered by the parent-portal <TwsiLogo> component.
@import url("https://fonts.googleapis.com/css2?family=Montserrat:wght@400;500;600;700&display=swap");

// -----------------------------------------------------------------
//  TWSI light-mode palette (brand guidelines page 3)
// -----------------------------------------------------------------
$primary:         #0B6E4F;   // Emerald Green — brand primary
$brand-cta:       #0FB67A;   // Emerald Action — CTA fill
$brand-hover:     #084D37;   // Dark Emerald — hover / pressed
$secondary:       #2B4162;   // Indigo Blue — headings + chrome
$accent:          #E1C15A;   // Soft Gold — highlights
$mint:            #6FD6B3;   // Fresh Mint — success/confirmation
$bg:              #F4FAF8;   // Soft Mint White — page bg
$surface:         #FFFFFF;   // Pure White — cards
$ink:             #2A2A2A;   // Charcoal — body text
$ink-muted:       #777777;   // Medium Grey — secondary text
$border:          #D7E4DD;   // Neutral-green divider
SCSS;

$twsi_scss_post = <<<'SCSS'
// -----------------------------------------------------------------
//  Typography — Montserrat everywhere (Cinzel is logo-only)
// -----------------------------------------------------------------
body,
.navbar,
.btn,
.form-control,
.card,
h1, h2, h3, h4, h5, h6 {
  font-family: "Montserrat", -apple-system, "Segoe UI", sans-serif;
}

h1, h2, h3, .h1, .h2, .h3 { font-weight: 700; }
h4, h5, h6, .h4, .h5, .h6 { font-weight: 600; }

// -----------------------------------------------------------------
//  Surfaces — soft mint bg, charcoal ink
// -----------------------------------------------------------------
body { background: #F4FAF8; color: #2A2A2A; }
.card,
.block,
#region-main { background: #FFFFFF; }

// -----------------------------------------------------------------
//  Primary buttons — emerald action with dark-emerald hover
// -----------------------------------------------------------------
.btn-primary,
.btn.btn-primary {
  background-color: #0FB67A;
  border-color: #0FB67A;
}
.btn-primary:hover,
.btn-primary:focus,
.btn-primary:active {
  background-color: #084D37 !important;
  border-color: #084D37 !important;
}

// Links + secondary chrome use the primary emerald
a, a:visited { color: #0B6E4F; }
a:hover { color: #084D37; }

// -----------------------------------------------------------------
//  Chrome cleanup — students are in a single quiz. Hide the
//  Moodle-native bits that don't belong on an admissions test.
// -----------------------------------------------------------------
.breadcrumb-nav { display: none; }
nav[aria-label="Navigation bar"] { display: none; }
.drawer[data-region="drawer"] .list-group-item[data-key="mycourses"] { display: none; }
#page-footer,
.footer-dark { display: none; }

// Quiz-specific polish — keep the attempt page uncluttered
#page-mod-quiz-attempt #region-main {
  border: 1px solid #D7E4DD;
  border-radius: 12px;
}
SCSS;

$CFG->forced_plugin_settings = [
    'theme_boost' => [
        // Raw SCSS slots — the ONLY correct names for Boost's custom
        // SCSS injection. `scsspre` / `scss` are deprecated and are
        // silently ignored by theme/boost/classes/output/core_renderer.php
        // (took a round of "why isn't the palette applying?" debugging
        // to catch this one — hence the hard-coded rename).
        //
        //   rawscsspre  runs BEFORE Boost's default _variables.scss,
        //               so $primary here wins over the stock Bootstrap
        //               blue when Boost compiles its SCSS bundle.
        //   rawscss     runs AFTER the compiled bundle, so pure CSS
        //               overrides here cascade over everything Boost
        //               generated.
        'rawscsspre' => $twsi_scss_pre,
        'rawscss'    => $twsi_scss_post,
        // Flat brand colour for the navbar + link hover shim.
        'brandcolor' => '#0B6E4F',
    ],
];

require_once(__DIR__ . '/lib/setup.php');
