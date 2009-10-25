#!perl -w

use lib 't';

use WWW'Scripter;

{ package ScriptHandler;
  sub new { shift; bless [@_] }
  sub eval { my $self = shift; $self->[0](@_) }
  sub event2sub { my $self = shift; $self->[1](@_) }
}

my @__;
(my $m = new WWW::Scripter)->script_handler(
 qr/javascript/i => new ScriptHandler sub { push @__, $_[1] }
);

use tests 4; # basic timeout tests
diag('This script (timers.t) pauses a few times.');
{
 package fake_code_ref;
 use overload fallback=>1,'&{}' =>sub{${$_[0]}}
}
$m->get('data:text/html,');
$m->setTimeout("42",2000);
$m->setTimeout(sub { push @__, 'scrext' }, 2000);
$m->setTimeout(
 bless(\sub { push @__, 'sked' }, fake_code_ref::),
 2000
);
$m->clearTimeout($m->setTimeout("43",2100));
$m->check_timers;
is "@__", '', 'before timeout';
$_ = 'crit';
is $m->count_timers, 3, 'count_timers';
is $_, 'crit', 'count_timers does not clobber $_'; # fixed in 0.008
sleep 3;
$m->check_timers;
is "@__", '42 scrext sked', 'timeout';

use tests 5; # frames
@__ = ();
$m->get('data:text/html,<iframe>');
$m->setTimeout('cile',500);
$m->frames->[0]->setTimeout('frew',501);
is $m->count_timers, 2, 'count_timers with frames';
sleep 1;
$m->check_timers;
is "@__", 'cile frew', 'check_timers with frames';
$m->frames->[0]->setTimeout('dat',500);
is $m->count_timers, 1, 'count_timers with timers only in frames';
sleep 1;
$m->check_timers;
is "@__", 'cile frew dat', 'check_timers with timers only in frames';
{
 my $w = new WWW::Scripter;
 $m->get('data:text/html,<iframe>');
 $m->frames->[0]->setTimeout('dat',500);
 is $m->count_timers, 1,
  'count_timers w/timers in frame when the main window has never had any';
  # Yes, this actually failed.
}


use tests 2; # errors
{
 my $w;
 local $SIG{__WARN__} = sub { $w = shift };
 $m->setTimeout(sub{die 'cror'}, 500);
 sleep 1;
 ok eval { $m->check_timers; 1 },
  'script errors do not cause check_timers to die';
 like $w, qr/^cror/, 'check_timers turns errors into warnings';
}
