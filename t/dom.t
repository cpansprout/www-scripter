#!perl -w

# Slightly modified version of WWW::Mechanize::Plugin::DOM’s dom.t
# (for now).
# Tests are gradually being moved from here into other files.

use strict; use warnings;
use lib 't';
use Test::More;

use utf8;

use HTML'DOM 0.03; # for the onload/unonload test
use Scalar::Util 1.09 'refaddr';
use URI;
use URI::file;
use WWW::Scripter;

sub data_url {
	my $u = new URI 'data:';
	$u->media_type('text/html');
	$u->data(shift);
	$u
}

{ package ScriptHandler;
  sub new { shift; bless [@_] }
  sub eval { my $self = shift; $self->[0](@_) }
  sub event2sub { my $self = shift; $self->[1](@_) }
}

use tests 4; # interface for callback routines
for my $lang ('default', qr//) {
	my $test_name = ref $lang ? 'with re' : $lang;
	my @result;
	my $event_triggered;

	my $m = new WWW::Scripter;
	$m->script_handler($lang => new ScriptHandler
		sub {
				push @result, "script",
				  map ref eq "URI::file" ? $_ : ref||$_, @_
		},
		sub {
				push @result, "event",
				 map ref eq "URI::file" ? $_ : ref||$_, @_;
				sub { ++ $event_triggered }
		}
	);
	my $uri = URI::file->new_abs( 't/dom-callbacks.html' );
	my $script_uri = URI::file->new_abs( 't/dom-test-script' );
	$m->get($uri);
	is_deeply \@result, [
		script =>
			'WWW::Scripter',
			"<!--\nthis is a short script\n-->",
			"$uri",
			 3,
			 1, # not normative; it just has to be true
		script =>
			'WWW::Scripter',
			"This is an external script.\n",
			"$script_uri",
			 1,
			 0, # not normative; it just has to be false
		event =>
			'WWW::Scripter',
			'HTML::DOM::Element::A',
			'click',
			'bar',
			"$uri",
			 8,
		event =>
			'WWW::Scripter',
			'HTML::DOM::Element::A',
			'click',
			'baz',
			"$uri",
			 9,
	], "callbacks ($test_name)"
	 or require Data'Dumper,
	    diag Data'Dumper'Dumper(\@result);
	$m->document->getElementsByTagName('a')->[0]->
		trigger_event('click');
	is $event_triggered,1, "event handlers ($test_name)";
}

use tests 1; # warnings caused by script tags and event handlers
{            # with no language
	my $warnings = 0;
	local $SIG{__WARN__} = sub { ++$warnings;};

	my $m = new WWW::Scripter;
	$m->script_handler(
			'foo' => qr//
	);
	$m->get(URI::file->new_abs( 't/dom-no-lang.html' ));
	is $warnings, 0, 'absence of a script language causes no warnings';
}

use tests 2; # charset
{     
	(my $m = new WWW::Scripter);
	$m->get(URI::file->new_abs( 't/dom-charset.html' ));
	is $m->document->title,
		'Ce mai faceţ?', 'charset';
	local $^W;
	$m->get(URI::file->new_abs( 't/dom-charset2.html' ));
	is $m->document->title,
		'Αὐτὴ ἡ σελίδα χρησιμοποιεῖ «UTF-8»', 'charset 2';
}

use tests 2; # get_text_content with different charsets
{            # (bug in 0.002 [Mech plugin])
	(my $m = new WWW::Scripter);
	$m->get(URI::file->new_abs( 't/dom-charset.html' ));
	like $m->content(format=>'text'), qr/Ce mai face\376\?/,
		 'get_text_content';
	local $^W;
	$m->get(URI::file->new_abs( 't/dom-charset2.html' ));
	my $qr = qr/
		\316\221\341\275\220\317\204\341\275\264\302\240\341
		\274\241[ ]\317\203\316\265\316\273\341\275\267\316\264\316
		\261[ ]\317\207\317\201\316\267\317\203\316\271\316\274\316
		\277\317\200\316\277\316\271\316\265\341\277\226[ ]\302\253
		UTF-8\302\273/x;
	like $m->content(format=>'text'), $qr,
		 'get_text_content on subsequent page';
}

use tests 5; # on(un)load
{
	my $events = '';
	my $target;
	(my $m = new WWW::Scripter)
	 ->script_handler(
			default => new ScriptHandler sub {}, sub {
				my $code = $_[3];
				sub {
				 $events .= $code; $target = shift->target
				}
			}
	);
	$m->get(URI::file->new_abs( 't/dom-onload.html' ));
	is $events, 'onlode', '<body onload=...';
	(my $doc = $m->document)->title('dom-onload modified');
	is $target, $doc, 'target of load event';
	$doc->addEventListener(
	 'onload', sub { $events = "This should never happen." }
	);
	$m->get(new_abs URI'file 't/blank.html');
	is $events, 'onlodeunlode', 'unload';
	$m->document->title("blank modified");
	$m->get('about:blank');
	$m->back;
	is $m->title, "blank modified",
	 'absence of onunload causes documents to persist';
	$m->back;
	is $m->title, "",
	 'presence of onunload causes documents to be discarded';
}

use tests 9; # scripts_enabled
{
	my $script_src;
	my $event;

	my $m = new WWW::Scripter;
	$m->script_handler(
			default => new ScriptHandler sub {
				$script_src = $_[1]
			}, sub {
				my $e = "@_[2,3]"; # event name & attr val
				sub { $event = $e }
			}
	);
	ok $m->scripts_enabled, 'scripts enabled by default';

	my $url = data_url(<<'END');
		<HTML><head><title>oetneotne</title></head>
		<body onclick="do stough">
		<script>this is a script</script>
END
	$m->scripts_enabled(0);
	$m->get($url);
	is $script_src, undef, 'disabling scripts works';
	$m->get($url);
	is $script_src, undef, 'the disabled settings survives a ->get';
	$m->scripts_enabled(1);
	$m->document->body->trigger_event('click');
	is $event, undef,
	  'disabling scripts stops event handlers from being registered';
	$m->get($url);
	is $script_src, 'this is a script', 're-enabling scripts works';
	$m->document->body->click;
	is $event, 'click do stough',
		'  and re-enables attr event handler registration as well';
	$event=undef;
	$m->scripts_enabled(0);
	$m->document->body->trigger_event('click');
	is $event, undef,
	   'disabling scripts disabled event handlers already registered';
	$m->scripts_enabled(1);
	$m->document->body->trigger_event('click');
	is $event, 'click do stough',
	' & re-enabling them re-enables event handlers already registered';

	$m->scripts_enabled(0);
	$m->onfoo(sub{$event = 42});
	$m->trigger_event('foo');
	isn't $event, 42,
	  'window event handlers are not called when scripts are off';
}

use tests 1; # window as part of event dispatch chain
{
	my $m = new WWW::Scripter;
	$m->get('data:text/html,');
	my $targets;
	$m                           ->onfoo(sub { $targets .= '-w' });
	$m->document                 ->onfoo(sub { $targets .= '-d' });
	$m->document->documentElement->onfoo(sub { $targets .= '-h' });
	$m->document->body      ->addEventListener( foo=>
	        sub { $targets .= '-b' });
	$m                      ->addEventListener( foo=>
		sub { $targets .= '-w(c)' },1);
	$m->document            ->addEventListener( foo=>
		sub { $targets .= '-d(c)' }, 1);
	$m->document->firstChild->addEventListener( foo=>
		sub { $targets .= '-h(c)' }, 1);
	$m->document->body      ->addEventListener( foo=>
		sub { $targets .= '-b(c)' }, 1);
	$m->document->body->trigger_event('foo');
	is $targets, '-w(c)-d(c)-h(c)-b-h-d-w',
		'window as part of the event dispatch chain';
}

use tests 1; # click events on links
{
	my $m = new WWW::Scripter ;
	my $other_url = data_url <<'END';
		<title>The other page</title><p>
END
	$m->get(data_url(<<END));
		<HTML><head><title>oetneotne</title></head>
		<a href="$other_url">click me </a>
END
	$m->document->links->[0]->click;
	is $m->document->title, 'The other page',
		'a click event on a link goes to the other page';
}

use tests 2; # Scripter->links
{
	my $m = new WWW::Scripter ;
	my $url = data_url <<'END';
		<title>A page</title><p>
		  <a name=link1 href=one.html target=a>Dis is link one.</a>
		  <a name=link2 href=two.html target=b>Dis is link two.</a>
		  <a name=link3 href=tri.html target=c>Diss link three.</a>
END
	$m->get($url);
#	my $base = $m->base;
# ~~~ We can’t test base for now, because of a URI bug.
	is_deeply [
		map {;
			my $link = $_;
			+{ map +($_ => $link->$_),
				qw[ url text name tag attrs ] }
		} $m->links
	], [
		{ url => 'one.html',
		  text => 'Dis is link one.',
		  name => 'link1',
		  tag  => 'a',
	#	  base => $base,
		  attrs => {
			name => 'link1', href => 'one.html', target => 'a',
		  }, },
		{ url => 'two.html',
		  text => 'Dis is link two.',
		  name => 'link2',
		  tag  => 'a',
	#	  base => $base,
		  attrs => {
			name => 'link2', href => 'two.html', target => 'b',
		  }, },
		{ url => 'tri.html',
		  text => 'Diss link three.',
		  name => 'link3',
		  tag  => 'a',
	#	  base => $base,
		  attrs => {
			name => 'link3', href => 'tri.html', target => 'c',
		  }, },
	], '$scripter->links'
	or require Data::Dumper, diag Data::Dumper::Dumper([
		map {;
			my $link = $_;
			+[ map +($_ => $link->$_),
				qw[ url text name tag attrs ] ]
		} $m->links
	]);

	my $link = $m->document->links->[1];
	$link->parentNode->removeChild($link);

	is_deeply [
		map {;
			my $link = $_;
			+{ map +($_ => $link->$_),
				qw[ url text name tag attrs ] }
		} $m->links
	], [
		{ url => 'one.html',
		  text => 'Dis is link one.',
		  name => 'link1',
		  tag  => 'a',
	#	  base => $base,
		  attrs => {
			name => 'link1', href => 'one.html', target => 'a',
		  }, },
		{ url => 'tri.html',
		  text => 'Diss link three.',
		  name => 'link3',
		  tag  => 'a',
	#	  base => $base,
		  attrs => {
			name => 'link3', href => 'tri.html', target => 'c',
		  }, },
	], '$scripter->links after a modification to the document'
	or require Data::Dumper, diag Data::Dumper::Dumper([
		map {;
			my $link = $_;
			+{ map +($_ => $link->$_),
				qw[ url text name tag attrs ] }
		} $m->links
	]);
	
}

use tests 2; # images
{
	my $m = new WWW::Scripter;
	my $url = data_url <<'END';
	  <title>A page</title><p>
	    <img name=link1 src=one.html width=1 height=2 alt='Dis '>
	    <input name=link2 src=two.html type=image width=3 height=4
	      alt='a'>
	    <img name=link3 src=tri.html width=6 height=87 alt='target=c>'>
END
	$m->get($url);
#	my $base = $m->base;
# ~~~ We can’t test base for now, because of a URI bug.
	is_deeply [
		map {;
			my $img = $_;
			+{ map +($_ => $img->$_),
				qw[ url tag name height width alt ] }
		} $m->images
	], [
		{ url => 'one.html',
	#	  base => $base,
		  tag  => 'img',
		  name => 'link1',
		  height => 2,
		  width => 1,
		  alt => 'Dis ', },
		{ url => 'two.html',
	#	  base => $base,
		  tag  => 'input',
		  name => 'link2',
		  height => 4,
		  width => 3,
		  alt => 'a', },
		{ url => 'tri.html',
	#	  base => $base,
		  tag  => 'img',
		  name => 'link3',
		  width => 6,
		  height => 87,
		  alt => 'target=c>', },
	], 'images'
	or require Data::Dumper, diag Data::Dumper::Dumper([
		map {;
			my $img = $_;
			+{ map +($_ => $img->$_),
				qw[ url tag name height width alt ] }
		} $m->images
	]);

	my $input = $m->document->find('input');
	$input->parentNode->removeChild($input);

	is_deeply [
		map {;
			my $img = $_;
			+{ map +($_ => $img->$_),
				qw[ url tag name height width alt ] }
		} $m->images
	], [
		{ url => 'one.html',
	#	  base => $base,
		  tag  => 'img',
		  name => 'link1',
		  height => 2,
		  width => 1,
		  alt => 'Dis ', },
		{ url => 'tri.html',
	#	  base => $base,
		  tag  => 'img',
		  name => 'link3',
		  width => 6,
		  height => 87,
		  alt => 'target=c>', },
	], 'images after a modification to the document'
	or require Data::Dumper, diag Data::Dumper::Dumper([
		map {;
			my $img = $_;
			+{ map +($_ => $img->$_),
				qw[ url tag name height width alt ] }
		} $m->images
	]);
}

use tests 3; # script encodings
{
	my $script_content;
	(my $m = new WWW::Scripter)
	 ->script_handler( default => new ScriptHandler sub {
			$script_content = $_[1];
		}) ;

	my $script_url = data_url "\xfe\xfd";
	$script_url->media_type(
		'application/javascript;charset=iso-8859-7'
	);
	my $html_url = data_url <<"END";
		<title>A page</title><script src='$script_url'></script><p>
END
	$m->get($html_url);
	is $script_content, 'ώύ', 'script encoding in the HTTP headers';

	$script_url->media_type('application/javascript');
	$html_url = data_url <<"END";
		<title>A page</title>
			<script src='$script_url'></script><p>
END
	$html_url->media_type('text/html;charset=iso-8859-5');
	$m->get($html_url);
	is $script_content, 'ў§',
		'script encoding inferred from the HTML page';

	$html_url = data_url <<"END";
		<title>A page</title>
		  <script charset=iso-8859-4 src='$script_url'></script><p>
END
	$m->get($html_url);
	is $script_content, 'ūũ',
		'script encoding from explicit charset param';
}

use tests 1; # DOM tree ->charset
{
	my $m = new WWW::Scripter;
	my $url = data_url <<'END';
		<title>A page</title><p>
END
	$url->media_type("text/html;charset=iso-8859-7");
	$m->get($url);

	is $m->document->charset, 'iso-8859-7',
		'the plugin sets the DOM tree\'s charset attribute';
}

use tests 1; # get_content and !doctype
{
	my $m = new WWW::Scripter;
	my $url = data_url <<'END';
		<!doctype html public "-//W3C//DTD HTML 4.01//EN">
		<title>A page</title><p>
END
	$m->get($url);

	like $m->content, qr/^<!doctype/,
		'get_content includes the doctype (if there was one)';
}

use tests 17; # (i)frames
{
	my $script;
	(my $m = new WWW::Scripter)
	 ->script_handler( default => new ScriptHandler sub {
			$script = $_[1];
		}) ;
	my $frame_url = data_url <<'END';
		<script>abcde</script>
END
	my $top_url = data_url <<END;
		<iframe id=i src="$frame_url">
END
	$m->get($top_url);

	my $w = $m;

	is $w->top, $w->window, 'top-level top refers to self';

	is $script, 'abcde', 'scripts in iframes run';
	is $w->frames->{i},
		(my $i = $w->document->getElementsByTagName('iframe')->[0])
		  ->contentWindow,
		'hash keys to access iframes';
	is $w->frames->[0], $i->contentWindow, 'array access to iframes';
	is $i->contentDocument,$w->frames->[0]->document,
	 'iframe->contentDocument';
	isn't $w->frames->[0], $w,
		'frames->[0] (the iframe) is not the top-level win';
	isn't $w->document, $i->contentDocument,
		"the iframe's doc is not the top window's doc";
	is $w->frames->[0]->top, $w,
	 "iframe's top method returns the main window";
	is $w->length, 1, 'window length when there is an iframe';


	$script = '';
	$top_url = data_url <<END;
		<frame id=the_frame src="$frame_url">
END
	$m->get($top_url);

	is $script, 'abcde', 'scripts in frames run';
	is $w->frames->{the_frame},
		($i = $w->document->getElementsByTagName('frame')->[0])
		  ->contentWindow,
		'hash keys to access frames';
	is $w->frames->[0], $i->contentWindow, 'array access to frames';
	is $i->contentDocument,$w->frames->[0]->document,
	 'frame->contentDocument';
	isn't $w->frames->[0], $w,
		'frames->[0] (the frame) is not the top-level window';
	isn't $w->document, $i->contentDocument,
		"the frame's doc is not the top window's doc";
	is $w->frames->[0]->top, $w,
	 "frame's top method returns the main window";
	is $w->length, 1, 'window length when there is a frame';
}

use tests 1; # gzipped scripts
{
	package ProtocolThatAlwaysReturnsTheSameThing;
	use LWP::Protocol;
	our @ISA = LWP::Protocol::;

	LWP'Protocol'implementor $_ => __PACKAGE__ for qw/ test /;

	sub request {
		my($self, $request, $proxy, $arg) = @_;
	
		my $h = new HTTP::Headers;
		$h->header('Content-Encoding', 'gzip');
		my $zhello = join '', map chr hex, qw[
		 1f 8b 08 00 02 5b 09 49 00 03 cb 48 cd c9 c9 07 00 86 a6
		 10 36 05 00 00 00
		];
		new HTTP::Response 200, 'OK', $h, $zhello
	}
}
{
 my $output;
 (my $m = new WWW::Scripter)
  ->script_handler( default => new ScriptHandler sub { $output = $_[1] } );
 $m->get(data_url '<script src="test://foo/"></script>');
 is $output, 'hello', 'gzipped scripts';
}

use tests 3; # timeouts
{
	my $__;
	(my $m = new WWW::Scripter)->script_handler(
	 qr/javascript/i => new ScriptHandler sub { $__ = $_[1] }
	);
	$m->get('data:text/html,');
	$__ = "nothing";
	$m->setTimeout("42",5000);
	$m->clearTimeout($m->setTimeout("43",5100));
	$m->check_timers;
	is $__, 'nothing', 'before timeout';
	is $m->count_timers, 1, 'count_timers';
	diag('pausing (timeout test)');
	sleep 6;
	$m->check_timers;
	is $__, '42', 'timeout';
}

use tests 3; # nested frames
{
	my $script;
	my $m = new WWW::Scripter;
	my $inner_frame_url = data_url "blah blah blah";
	my $outer_frame_url = data_url <<END;
		<iframe id=innerframe src="$inner_frame_url">
END
	my $top_url = data_url <<END;
		<iframe id=outerframe src="$outer_frame_url">
END
	$m->get($top_url);


	is $m->frames->{outerframe}->frames->{innerframe}->top, $m,
	 'top property accessed from nested frame';

	is $m->frames->{outerframe}->frames->{innerframe}->parent,
	 $m->frames->{outerframe},
	 'parent of inner frame';
	is $m->parent, $m, 'top-level window is its own parent';
}

use tests 1; # re-use of document objects when browsing history
{
 my $w = new WWW::Scripter;
 $w->get("about:blank");
 my @refaddrs = refaddr $w->document;
 $w->get("data:text/html,foo");
 push @refaddrs, refaddr $w->document;
 $w->back;
 push @refaddrs, refaddr $w->document;
 like join('-',@refaddrs), qr/^(\d+)-(?!\1)\d+-\1\z/,
  'going back reuses the same document object';
}

use tests 2; # frames method with non-HTML documents
{            # This used to die before version 0.004
 my $w = new WWW::Scripter;
 $w->get("data:text/plain,");
 is +()=$w->frames, 0, 'frames returns 0 in list context with a text doc';
 is @{ $w->frames }, 0, 'frames collection is empty with a text doc';
}

use tests 4; # about:blank before browsing
{
 my $w = new WWW::Scripter;
 is $w->uri, "about:blank",
  "about:blank uri before browsing";
 is $w->ct, "text/html", "ct before browsing";
 is $w->response->content, "", "content before browsing";
 ok $w->document,, "document before browsing";
}
