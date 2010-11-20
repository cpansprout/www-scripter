#!perl -w

use lib 't';
use WWW'Scripter;

use tests 1;

use Scalar::Util 'weaken';

$w = new WWW'Scripter;
$res = $w->res;
undef $w;
weaken $res;
is $res, undef, 'no circular references between response and doc';
