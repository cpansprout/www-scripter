#!perl -w

use lib 't';

use utf8;

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

use tests 3; # images
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
	
	my $image = ($m->images)[0];
 	my $dom_img = $m->document->images->[0];
	$dom_img->src("glat");
	is $image->url, 'glat',
	  'images update automatically when their HTML elements change';
}
