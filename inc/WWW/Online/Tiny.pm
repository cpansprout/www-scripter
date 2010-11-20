# This is a plagiarised version of LWP::Online, which only supports HTTP
# and does not require LWP, so it is appropriate for use in a Makefile.PL.

package WWW::Online::Tiny;

use 5.005;
use strict;
use Carp 'croak';

sub get {
 require IO'Socket'INET;
 my $sock
  = new IO'Socket'INET Proto => tcp => PeerAddr => $_[0], PeerPort => '80',
                       Timeout => 5
                      # I’m using 5, not 30 (as LWP::Online does), since a
                      # Makefile.PL will appear to have hung otherwise.
   or return;
 autoflush $sock 1;
 print $sock "GET $_[1] HTTP/1.0\015\012\015\012";
 local $/;
 <$sock>;
}

use vars qw{$VERSION @ISA @EXPORT_OK};
BEGIN {
#	$V E R S I O N = '1.07';

	# We are an Exporter
	require Exporter;
	@ISA       = qw{ Exporter };
	@EXPORT_OK = qw{ online offline };
}

# Set up configuration data
use vars qw{@RELIABLE_HTTP};
BEGIN {
	# (Relatively) reliable websites
	@RELIABLE_HTTP = (
		# These are some initial trivial checks.
		# The regex are case-sensitive to at least
		# deal with the "couldn't get site.com case".
		'google.com', '/' => sub { /About Google/      },
		'yahoo.com' , '/' => sub { /Yahoo!/            },
		'amazon.com', '/' => sub { /Amazon/ and /Cart/ },
		'cnn.com'   , '/' => sub { /CNN/               },
	);
}

sub import {
	my $class = shift;

	# Handle the :skip_all special case
	my @functions = grep { $_ ne ':skip_all' } @_;
	if ( @functions != @_ ) {
		require Test::More;
		unless ( online() ) {
			Test::More->import( skip_all => 'Test requires a working internet connection' );
		}
	}

	# Hand the rest of the params off to Exporter
	return $class->export_to_level( 1, $class, @functions );
}





#####################################################################
# Exportable Functions

sub online {
	goto & http_online;
}

sub offline {
	! online(@_);
}





#####################################################################
# Transport Functions

sub http_online {
	# Check the reliable websites list.
	# If networking is offline, an error/paysite page might still
	# give us a page that matches a page check, while any one or
	# two of the reliable websites might be offline for some
	# unknown reason (DDOS, earthquake, chinese firewall, etc)
	# So we want 2 or more sites to pass checks to make the
	# judgement call that we are online.
	my $good     = 0;
	my $bad      = 0;
	my @reliable = @RELIABLE_HTTP;
	while ( @reliable ) {
		# Check the current good/bad state and consider
		# making the online/offline judgement call.
		return 1  if $good > 1;
		return '' if $bad  > 2;

		# Try the next reliable site
		my $site  = shift @reliable;
		my $path  = shift @reliable;
		my $check = shift @reliable;

		# Try to fetch the site
		my $content;
		SCOPE: {
			local *@;
			$content = eval { get($site,$path) };
			if ( $@ ) {
				# An exception is a simple failure
				$bad++;
				next;
			}
		}
		unless ( defined $content ) {
			# get() returns undef on failure
			$bad++;
			next;
		}

		# We got _something_.
		# Check if it looks like what we want
		for($content) {
			if ( $check->() ) {
				$good++;
			} else {
				$bad++;
			}
		}
	}

	# We've run out of sites to check... erm... uh...
	# We should probably fail conservatively and say not online.
	return '';
}

1;

__END__

Copyright notice from LWP::Online:

Copyright 2006 - 2008 Adam Kennedy.

This program is free software; you can redistribute
it and/or modify it under the same terms as Perl itself.

The full text of the license can be found in the
LICENSE file included with this module.
