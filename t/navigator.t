#!perl -w

use lib 't';
use WWW'Scripter;

$w = new WWW'Scripter;
$n = $w->navigator;

use tests 10;
is $n->userAgent, $w->agent,'userAgent';
is $n->appName, 'WWW::Scripter', 'initial appName';
is $n->appName('scow'), 'WWW::Scripter', 'retval of appName when setting';
is $n->appName, 'scow', 'result of setting appName';
is $n->appCodeName, 'WWW::Scripter', 'initial appCodeName';
is $n->appCodeName('creen'), 'WWW::Scripter',
 'retval of appCodeName when setting';
is $n->appCodeName, 'creen', 'result of setting appCodeName';
is $n->appVersion, 'WWW::Scripter'->VERSION, 'initial appVersion';
is $n->appVersion('cnelp'), 'WWW::Scripter'->VERSION,
 'retval of appVersion when setting';
is $n->appVersion, 'cnelp', 'result of setting appVersion';

{
 package ghin;
 @ISA = WWW'Scripter;
}

use tests 1;
is new ghin ->navigator->appName,  'ghin',
 'appName from empty WWW::Scripter subclass';
