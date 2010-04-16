#!perl -w

use lib 't';

use URI;
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

use tests 3; # Scripter->links
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
	
	$link = ($m->links)[0];
 	my $dom_link = $m->document->links->[0];
	$dom_link->href("stred");
	is $link->url, 'stred',
	  'links update automatically when their HTML elements change';
}

use tests 6; # follow_link
for(""," with autocheck")
{
 my $w = new WWW'Scripter autocheck => $_;
 $w->script_handler(default => new ScriptHandler sub{},sub {
  my $code = $_[3];
  eval "sub { $code }"
 });
 $w->get(data_url <<'');
  <a href='cleck'
     onclick='shift->target->href("data:text/html,cting")'>frare</a>

 my $res = $w->follow_link(text=>'frare');
 is $w->location, 'data:text/html,cting',
  "follow_link runs event handlers$_";
 is $res, $w->res, "retval of follow_link$_";
 like 
   eval {
    $w->get(data_url "<a href='data:text/html,slext' onclick=0>czon</a>");
    $w->follow_link(text => 'czon');
    join " ", $w->location, $w->history->length
   },
   qr "czon\S+ 3\z",
  "follow_link$_ can be intercepted by event handlers";
}
