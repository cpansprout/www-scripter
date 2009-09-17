BEGIN { require 5.006 } # our

use ExtUtils::MakeMaker;

WriteMakefile(
    NAME            => 'WWW::Scripter',
    AUTHOR          => 'Father Chrysostomos <sprout at, um, cpan dot org>',
    VERSION_FROM    => 'lib/WWW/Scripter.pm',
    ABSTRACT_FROM   => 'lib/WWW/Scripter.pod',
    PL_FILES            => {},
    PREREQ_PM => {
	Encode                     => 0,
	Exporter                   => 5.57,
	Hash'Util'FieldHash'Compat => 0,
	HTML::DOM                  =>  .03, # body->onion delegates to win
	HTML'DOM'Collection        => 0,
	HTML'DOM'EventTarget       =>  .03, # attr_event_listener (only for
	HTML::DOM::Interface       =>  .019, # EventTarget  # delegation)
	HTML::DOM::NodeList::Magic =>  .020, # 2nd arg to new
	HTML'DOM'View              =>  .018, # inside-out; writa-
	HTTP::Headers::Util        => 0,     # ble document
	HTTP::Message              => 1.34, # array ref headers
	HTTP::Request              => 1.29, # URI instead of URI::URL
	HTTP'Response              => 1.35, # likewise
	LWP                        => 5,
	LWP::Protocol              => 0, # version 1.22 at the earliest
	overload                   => 0,  # (LWP 5), for the collect
	Scalar::Util               => 0,   # method, but that version
	strict                     => 0,    # didn’t include $VERSION
	URI                        => 0,
	warnings                   => 0,
	WWW::Mechanize             => (
	 eval {
	  require LWP::UserAgent and
	      LWP'UserAgent->VERSION < 5.815 && LWP'UserAgent->VERSION >= 5
	  or require HTTP::Message and HTTP'Message->VERSION >= 1.34
	  or require HTTP::Request and HTTP'Request->VERSION >= 1.29
	  or require HTTP'Response and HTTP'Response->VERSION >= 1.35
	 }
	  ? 1.2 # cookie cloning
	  : 1.52 # compatibility with LWP 5.815 with regard to credentials
	),
	WWW::Mechanize::Image      => 0,
	WWW::Mechanize::Link       => 0,
# for testing:
	HTML'DOM      =>  .03, # doc->title when title elem is empty
	lib           => 0,
	Scalar'Util   => 1.09, # refaddr
	Test::More    => 0,
	URI::data     => 0,
	URI::file     => 0,
	utf8          => 0,
    },
    dist               => { COMPRESS => 'gzip -9f', SUFFIX => 'gz',
                            TAR => 'COPYFILE_DISABLE=1 tar' },
    clean              => { FILES => 'WWW-Scripter-*' },
);
