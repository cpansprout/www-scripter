BEGIN { require 5.006 } # our

use ExtUtils::MakeMaker;
use lib 'inc';
use WWW'Online'Tiny online;

my $required_mech_version
 =	eval {
	   require LWP::UserAgent and
	      LWP'UserAgent->VERSION < 5.815 && LWP'UserAgent->VERSION >= 5
	   and require HTTP::Message and HTTP'Message->VERSION >= 1.34
	   and require HTTP::Request and HTTP'Request->VERSION >= 1.29
	   and require HTTP'Response and HTTP'Response->VERSION >= 1.35
	}
	   ? 1.2 # cookie cloning
	   : 1.52 # compatibility with LWP 5.815 with regard to credentials
;

my %prereq = (
	CSS'DOM'Interface          => 0,
	Encode                     => 0,
	Exporter                   => 5.57,
	HTML::DOM                  =>  .045, # weaken_response
	HTML'DOM'Collection        => 0,
	HTML'DOM'EventTarget       =>  .034, # get_event_listeners  that
	                                            # does not close over
	HTML::DOM::Interface       =>  .019, # EventTarget  # the  target
	HTML::DOM::NodeList::Magic =>  .020, # 2nd arg to new            
	HTML'DOM'View              =>  .018, # inside-out; writa-
	HTTP::Headers::Util        => 0,     # ble document
	HTTP::Message              => 1.34, # array ref headers
	HTTP::Request              => 1.29, # URI instead of URI::URL
	HTTP'Response              => 1.35, # likewise
	List'Util                  => 0,
	LWP                        => 5,
	LWP::Protocol              => 0, # version 1.22 at the earliest
	                                     # (LWP 5), for the collect
	overload                   => 0,          # method, but that ver-
	Scalar::Util               => 1.09, # reftype  # sion  didn’t  in-
	strict                     => 0,                   # clude $VERSION
	eval { require Hash::Util::FieldHash } ? () : (
	 Tie'RefHash'Weak          => 0.08, # fieldhash
	),
	Time'HiRes                 => 0,
	URI                        => 0,
	warnings                   => 0,
	!eval {
	  require WWW::Mechanize;
	  VERSION WWW::Mechanize $required_mech_version
	 } && offline ? () : (
	  WWW::Mechanize           => $required_mech_version,
	  WWW::Mechanize::Image    => 0,
	  WWW::Mechanize::Link     => 0,
	),
# for testing:
#	HTML'DOM      =>  .03, # doc->title when title elem is empty
	HTML'DOM'Element'Form => .039, # make_request with GET and data:
	lib           => 0,
	Scalar'Util   => 1.09, # refaddr
	Test::More    => 0,
	URI::data     => 0,
	URI::file     => 0,
	utf8          => 0,
);

# If the prerequisites do not include WWW::Mechanize, then this is probably
# an off-line computer that cannot install it and WWW::Scripter will fall
# back to WWW::Scripter::_Mechanize. In that case, we have to declare
# WWW::Scripter::_Mechanize’s prerequisites.
if(!$prereq{'WWW::Mechanize'}) {
 my %mech_preq = (
        'Carp'                      => 0,
        'HTML::Form'                => 1.038,
        'HTML::HeadParser'          => 0,
        'HTML::TokeParser'          => 2.28,
         HTML::TreeBuilder          => 0,
        'HTTP::Request'             => 1.30,
         HTTP::Request::Common      => 0,
        'LWP::UserAgent'            => 5.827,
         strict                     => 0,
        'URI::URL'                  => 0,
         warnings                   => 0,
 );
 while(my($mod,$ver) = each %mech_preq) {
  $prereq{$mod} = $ver if $prereq{$mod} <= $ver;
 }                                   # ‘<=’, so 0 replaces undef
}

WriteMakefile(
    NAME            => 'WWW::Scripter',
    AUTHOR          => 'Father Chrysostomos <sprout at, um, cpan dot org>',
    VERSION_FROM    => 'lib/WWW/Scripter.pm',
    ABSTRACT_FROM   => 'lib/WWW/Scripter.pod',
    PL_FILES            => {},
    PREREQ_PM          => \%prereq,
    dist               => { COMPRESS => 'gzip -9f', SUFFIX => 'gz',
                            TAR => 'COPYFILE_DISABLE=1 tar' },
    clean              => { FILES => 'WWW-Scripter-*' },
);
