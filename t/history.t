#!perl

use warnings;
use strict;
use Test::More tests => 14 ;
use URI;

BEGIN {
    use_ok( 'WWW::Scripter' );
}

sub data_url {
    my $u = new URI 'data:';
    $u->media_type('text/html');
    $u->data(shift);
    $u
}

my $mech = WWW::Scripter->new;

is $mech->history->length, 1,'history->length\'s initial retval';

$mech->get(data_url '<title>first page</title>');
$mech->get(data_url '<title>second page</title>');
$mech->get(data_url '<title>third page</title>');
is $mech->history->length, 3, 'history->length after fetching pages';
$mech->back;
is $mech->history->length, 3, 'history->length after going back';
is $mech->title, 'second page', 'back';
$mech->back;
is $mech->title, 'first page', 'back again';
$mech->forward;
is $mech->title, 'second page', 'forward';
$mech->forward;
is $mech->title, 'third page', 'forward again';
$mech->back;
is $mech->title, 'second page', 'back yet again';

$mech->get(data_url '<title>new page</title>');
is $mech->history->length, 3,
    'history->length after a page fetch erases fwd history';
$mech->forward;
is $mech->title, 'new page', '->request erases the forward stack';
$mech->back;
is $mech->title, 'second page',
    'Does ->forward at the end of history mess things up?';

$mech->clear_history;
$mech->back;
is $mech->history->length, 1,
    'make sure back messes nothing up when you can\'t go back';


# state info stuff

$mech->get(data_url '<title>third page</title>');

my @scratch;
sub record_state {
    my $h = $mech->history;
    # Yes, we are breaking encapuslation here.
    # Don’t do this in your own code.
    my $history_entry = $h->[$h->index];
    push @scratch, [
     $mech->title,
     exists $history_entry->[3] ? $history_entry->[3] : undef
    ];
}

my $h = $mech->history;
$h->pushState(37);      record_state;
$h->pushState(43);      record_state;
$mech->get(data_url '<title>fourth page</title>'); record_state;
$h->pushState(\'phoo'); record_state;
$mech->back,                     record_state  for 1..5;
$mech->forward,                  record_state  for 1..6;
$mech->get(data_url '<title>fifth page</title>');
$mech->history->go(-2);
$h->pushState(\'barr'); # make sure it erases state objects from fwd
                        # history (that belong to the current page)
$mech->forward;                  record_state;

is_deeply \@scratch, [
    ['third page',  37],
    ['third page',  43],
    ['fourth page', undef],
    ['fourth page', \'phoo'],
    ['fourth page', undef],
    ['third page',  43],
    ['third page',  37],
    ['third page',  undef],
    ['second page', undef],
    ['third page',  undef],
    ['third page',  37],
    ['third page',  43],
    ['fourth page', undef],
    ['fourth page', \'phoo'],
    ['fourth page', \'phoo'],  # can't go forward beyond the last state
    ['fifth page', undef],
], 'pushState';
