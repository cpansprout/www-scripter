#!perl

use warnings;
use strict;
use Test::More tests => 16;

BEGIN {
    use_ok( 'WWW::Scripter' );
}


my $mech = WWW::Scripter->new;
isa_ok( $mech, 'WWW::Scripter', 'Created object' );

my $h = $mech->history;

is( $h->length, 1, 'Page stack starts with one item' );
ok( $mech->get('data:text/html,')->is_success, 'Got start page' );
is( $h->length, 1, 'Page stack still has one item after first GET' );
$mech->get('about:blank');
is( $h->length, 2, 'Pushed item onto page stack' );
$mech->get('data:text/html,foofoo');
is( $h->length, 3, 'Pushed another item onto page stack' );
$mech->clear_history();
is( $h->length, 1, 'clear_history clears it' );
like( $mech->content, qr/foofoo/,        'but leaves the page there' );
$mech->clear_history();
like( $mech->content, qr/foofoo/,             'even when I do it again' );
$mech->clear_history('Come on, do it properly!');
is( $mech->{uri}, undef,             "Alright, *now* it's gone." );
$mech->clear_history('again');
is( $h->length, 1, "and repeating it" );
is( $mech->{uri}, undef,              "doesn't seem" );
$mech->clear_history();
is( $h->length, 1, "to hurt" );
is( $mech->{uri}, undef,              "at all" );

$mech->get('data:text/html,');
$mech->get('data:text/html,oooo');
$mech->back();
$mech->clear_history();
is $h->index, 0, 'clear_history also erases forward history';

