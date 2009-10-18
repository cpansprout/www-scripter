#!perl -w

use lib 't';
use warnings;
no warnings qw 'utf8 parenthesis regexp once qw bareword syntax';

use WWW'Scripter;
$w = new WWW'Scripter;

use tests 1; # Multiple <base> tags.
$w->get('data:text/html,
 <base href="http://websms.rogers.page.ca/skins/rogers-oct2009/">
 <base href="http://websms.rogers.page.ca/skins/rogers-oct2009/">
');
is $w->base, "http://websms.rogers.page.ca/skins/rogers-oct2009/", 
   'base with multiple <base> tags';
