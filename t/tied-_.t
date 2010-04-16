#!perl -w

# ~~~ This test needs to be modified to created a tied $_ on its own, in
#     case the implementation of ->links changes.

use WWW::Scripter;
$w = new WWW::Scripter;

use Test::More tests => 1;

# Part of target.t which used to die:
$w->get(
  q|data:text/html,<iframe src="|
 . q|data:text/html,<iframe name=crelp>|
 .q|"></iframe><a target=crelp href="data:text/html,">|
);
$w->follow_link(n=>1);
$w->frames->[0]->get('about:blank');
for($w->document->links->[0]) {  # Put a tied scalar in *_
 $_->href("data:text/html,czeen");
 $_->click;
}

pass('tied $_ is left alone when pages are fetched');
