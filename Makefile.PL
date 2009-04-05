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
	HTML::DOM                  =>  .021, # contentWindow
	HTML'DOM'Collection        => 0,
	HTML'DOM'EventTarget       => 0,
	HTML::DOM::Interface       =>  .019, # EventTarget
	HTML::DOM::NodeList::Magic =>  .020, # 2nd arg to new
	HTML'DOM'View              =>  .018, # inside-out; writa-
	HTTP::Headers::Util        => 0,     # ble document
	LWP                        => 5,
	LWP::Protocol              => 0, # version 1.22 at the earliest
	overload                   => 0,  # (LWP 5), but that version
	Scalar::Util               => 0,   # didn’t include the VERSION var
	strict                     => 0,
	URI                        => 0,
	warnings                   => 0,
	WWW::Mechanize             => 1.3, # cookie clones
	WWW::Mechanize::Image      => 0,
	WWW::Mechanize::Link       => 0,
# for testing:
	lib         => 0,
	Scalar'Util => 1.09, # refaddr
	Test::More  => 0,
	URI::data   => 0,
	URI::file   => 0,
	utf8        => 0,
    },
    dist               => { COMPRESS => 'gzip -9f', SUFFIX => 'gz',
                            TAR => 'COPYFILE_DISABLE=1 tar' },
    clean              => { FILES => 'WWW-Scripter-*' },
);
