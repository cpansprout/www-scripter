use 5.006;

package WWW::Scripter;

our $VERSION = '0.005';

use strict; use warnings; no warnings qw 'utf8 parenthesis bareword';

use CSS'DOM'Interface;
use Encode qw'encode decode';
use Exporter 5.57 'import';
use Hash::Util::FieldHash::Compat qw 'fieldhash fieldhashes';
use HTML::DOM 0.021;
use HTML::DOM::EventTarget 0.03;
use HTML::DOM::Interface 0.019 ':all';
use HTML::DOM::View .018;
use HTTP::Headers::Util 'split_header_words';
use HTTP::Response;
use HTTP::Request;
use Scalar::Util qw 'blessed weaken';
use LWP::UserAgent;
BEGIN {
 require WWW::Mechanize;
 VERSION WWW::Mechanize $LWP::UserAgent::VERSION >= 5.815 ? 1.52 : 1.2
 # Version 1.52 is necessary for LWP 5.815 compatibility. Version 1.2 is
 # needed otherwise for its handling of cookie jars during cloning.
}
our @ISA = qw( WWW::Mechanize HTML::DOM::View );

sub DOES {
 return 1 if $_[1] eq 'HTML::DOM::EventTarget';
 goto &{$_[0]->can("SUPER::DOES")||return}
}

our @EXPORT_OK = qw/abort/;
our %EXPORT_TAGS = (
    all      => \@EXPORT_OK,
);

# Fields that we don’t want fiddled with when the page stack is
# manipulated:
fieldhashes \my( %scriptable, %script_handlers,
                 %class_info, %navi, %top, %parent );
# ~~~ Actually, most of these can be eliminated, since we can store them
#     directly in the object, as we are not doing that cloning that Mech
#     used to do between pages.

# Fields keyed by document:
fieldhashes \my( %timeouts, %frames, %evtg );

fieldhash my %document; # keyed by response — we actually use
                        # HTML::DOM::View’s storage for the current doc,
                        # but this field hash is necessary when we return
                        # to a page.

# These are used to create a link between a WWW::Mechanize::(Image|Link)
# object and the DOM equivalent.
fieldhash my %dom_obj;

# ------------- Mech overrides (or does it?) ------------- #

sub new {
	my $class = shift;
	my %args = @_;
	exists $args{max_docs}
	 and $args{stack_depth} = -1+delete$args{max_docs};
	my $max_history = delete $args{max_history};

	my $self = $class->SUPER::new(%args);

	$$self{Scripter_max_hist} = $max_history;
	$script_handlers{$self} = {};
	$scriptable{$self} = 1;

	$self->{page_stack} = WWW'Scripter'History->new( $self );

	weaken(my $self_fc = $self); # for closures
	$class_info{$self} = [
	 \(%HTML::DOM'Interface, %CSS'DOM'Interface, our%Interface), {
	  'WWW::Scripter::Image' => "Image",
	   Image                 => {
	    _constructor => sub {
	     my $i = $self_fc->document->createElement('img');
	     @_ and $i->attr('width',shift);
	     @_ and $i->attr('height',shift);
	     $i
	    }
	   },
	 }
	];

	unless(exists $args{agent}) {
		$self->agent("WWW::Scripter/$VERSION");
	}

	# I would like to avoid doing this when it is not necessary, but
	# the alternative would  require  overriding  HTML::DOM::View’s
	# document method, and that might slow things down more, since
	# document  is called more often than new  Scripter  objects
	# are created.
	_initial_page($self);

	$self;
}

sub _initial_page {
	my $req = new HTTP::Request 'GET', 'about:blank';
	my $res = new HTTP::Response 200, OK => [
	 'content-length' => 0,
	 'content-type' => 'text/html',
	], '';
	$res->request($req);
	shift->_update_page(
	 $req, $res
	);
}

sub clone {
	my $clone = (my $self = shift)->SUPER::clone(@_);
	$$_{$clone}=$$_{$self} for \(
	 %scriptable,%script_handlers
	);
	$clone->{handlers} = $self->{handlers};
	$clone->{page_stack} = WWW'Scripter'History->new($clone);
	$clone->_clone_plugins;
	$clone;
}

# for efficiency’s sake; not actually necessary
sub title { (shift->document||return)->title }

sub content {
	my $self = shift;
	if($self->is_html) {
		my %parms = @_;
		my $cs = (my $doc = $self->document)->charset;;
		if(exists $parms{format} && $parms{format} eq 'text') {
			my $text = $doc->documentElement->as_text;
			return defined $cs ? encode $cs, $text : $text;
		}
		my $content = $doc->innerHTML;
		$content = encode $cs, $content if defined $cs;
		$self->{content} = $content; # banana
	}
	$self->SUPER::content(@_);
}

#sub discontent { ... }

# banana galore!
sub follow_link {
	no warnings 'redefine';
	my $self = shift;
	local *find_link = sub {
		my $link = shift->SUPER::find_link(@_);
		return unless $link;
		my $ret;
		$dom_obj{$link}->trigger_event('click',
			DOMActivate_default => sub { $ret = $link }
		);
		$ret;
	};
	return $self->SUPER::follow_link(@_);
}


sub request {
    my $self = shift;
    return unless defined(my $request = shift);

    $request = $self->_modify_request( $request );

    my $meth = $request->method;
    my $orig_uri = $request->uri;
    my $skip_fetch;
    if(defined($orig_uri->fragment)) {
     (my $new_uri = $orig_uri->clone)->fragment(undef);
     $request->uri($new_uri);

     # Skip fetching the URL if it is the same (and there is a fragment).
     # We don’t need to strip the fragment from $self->uri before compari-
     # son as that always contains the actual URL  sent  in  the  request.
     $meth eq "GET" and $new_uri->eq($self->uri) and ++$skip_fetch;
    }

    my $response;

    if($skip_fetch) {
     $response = $self->response;
    }
    else {
     Scripter_REQUEST: {
        Scripter_ABORT: {
            $response = $self->_make_request( $request, @_ );
            last Scripter_REQUEST;
        }
        return 1
     }
    }

    if ( $meth eq 'GET' || $meth eq 'POST' ) {
        $self->get_event_listeners('unload') and
         $self->trigger_event('unload'),
         $self->{page_stack}->_delete_res;

        $self->{page_stack}->${\(
         $self->{Scripter_replace} ? '_replace' : '_add'
        )}($request, $response, $orig_uri);
    }

    $self->_update_page($request, $response);
}

# The only difference between this one and Mech is the args to
# decoded_content. I.e., this is the way Mech *used* to work.
sub _update_page {
    my ($self, $request, $res) = @_;

    $self->{req} = $request;
    $self->{redirected_uri} = $request->uri->as_string;

    $self->{res} = $res;

    $self->{status}  = $res->code;
    $self->{base}    = $res->base;
    $self->{ct}      = $res->content_type || '';

    if ( $res->is_success ) {
        $self->{uri} = $self->{redirected_uri};
        $self->{last_uri} = $self->{uri};
    }

    if ( $res->is_error ) {
        if ( $self->{autocheck} ) {
            $self->die( 'Error ', $request->method, 'ing ', $request->uri, ': ', $res->message );
        }
    }

    $self->_reset_page;

    # Try to decode the content. Undef will be returned if there's nothing to decompress.
    # See docs in HTTP::Message for details. Do we need to expose the options there?
    my $content = $res->decoded_content(charset => "none");
    $content = $res->content if (not defined $content);

    $content .= WWW::Mechanize::_taintedness();

    if ($self->is_html) {
        $self->update_html($content);
    }
    else {
        $self->{content} = $content;
    }

    return $res;
} # _update_page

sub update_html {
	my ($self,$src) = @_;

	# Restore an existing document (in case we are coming back from
	# another page).
	my $res = $self->{res};
	if(my $doc = $document{$res}) {
		$self->document($doc);
		$self->{form} = ($self->{forms} = $doc->forms)->[0];
		return;
	}

	my $life_raft = $self;
	weaken($self);

	$self->document($document{$res} = my $tree = new HTML::DOM
			response => $res,
			cookie_jar => $self->cookie_jar);

	$tree->error_handler(sub{$self->warn($@)});

	$tree->default_event_handler_for( link => sub {
		$self->get(shift->target->href)
	});
	$tree->default_event_handler_for( submit => sub {
		$self->request(shift->target->make_request);
	});

	if(%{$script_handlers{$self}}) {
		my $script_type = $res->header(
			'Content-Script-Type');
		defined $script_type or $tree->elem_handler(meta =>
		    sub {
			my($tree, $elem) = @_;
			return unless lc $elem->attr('http-equiv')
				eq 'content-script-type';
			$script_type = $elem->attr('content');
		});

		$tree->elem_handler(script => sub {
			    return unless $scriptable{$self};
			    my($tree, $elem) = @_;

			    my $lang = $elem->attr('type');
			    defined $lang
			        or $lang = $elem->attr('language');
			    defined $lang or $lang = $script_type;

			    my $uri;
			    my($inline, $code, $line) = 0;
			    if($uri = $elem->attr('src')) {
			        my $clone = $self->clone->clear_history(1);
			        require URI;
			        my $base = $self->base;
   			        $uri = URI->new_abs( $uri, $base )
			            if $base;
			        my $res = $clone->get($uri);
			        $res->is_success or 
			          $self->warn("couldn't get script $uri: "
			            . $res->status_line
			          ),
			          return;

			        # Find out the encoding:
			        my $cs = {
			          map @$_,
			          split_header_words $res->header(
			            'Content-Type'
			          )
	 		        }->{charset};

			        $code = decode $cs||$elem->charset
			            ||$tree->charset||'latin1',
			          $res->decoded_content(charset=>'none');
			        
			        
			        $line = 1;
			    }
			    else {
			        $code = $elem->firstChild->data;
			        ++$inline;
			        $uri = $self->uri;
			        $line = _line_no(
					$src,$elem->content_offset
			        );
			    };
	
			    my $h = $self->_handler_for_lang($lang);
			    $h && $h->eval($self, $code,
			                   $uri, $line, $inline);
			    $@ and $self->warn($@);
		});

		$tree->elem_handler(noscript => sub {
				return unless $scriptable{$self};
				$_[1]->detach#->delete;
				# ~~~ delete currently stops it from work-
				#     ing; I need to looook into this.
		});

		$tree->event_attr_handler(sub {
				return unless $scriptable{$self};
				my($elem, $event, $code, $offset) = @_;
				my $lang = $elem->attr('language');
				defined $lang or $lang = $script_type;

			        my $uri = $self->uri;
			        my $line = defined $offset ? _line_no(
					$src, $offset
			        ) : undef;

				my $h = $self->_handler_for_lang($lang);
				$h && $h->event2sub(
					$self,$elem,$event,$code,$uri,$line
				);
		});
	}

	$tree->elem_handler(noscript => sub {
		return if $scriptable{$self} && %{$script_handlers{$self}};
		$_[1]->replace_with_content->delete;
		# ~~~ why does this need delete?
	});

	$tree->defaultView(
		$self
	);
	$tree->event_parent($self);
	$tree->set_location_object($self->location);

	$tree->elem_handler(iframe => my $frame_handler = sub {
		my ($doc,$elem) = @_;
		my $subwin = $self->clone->clear_history(1);
		$elem->contentWindow($subwin);
		$subwin->_set_parent(my $parent = $doc->defaultView);
		defined(my $src = $elem->src) or return;
		$subwin->get(new_abs URI $src, $parent->base);
	});
	$tree->elem_handler(frame => $frame_handler);

	# Find out the encoding:
	my $cs = {
		map @$_,
		split_header_words $res->header('Content-Type')
	 }->{charset};
	$cs or $res->can('content_charset')
	       and $cs = $res->content_charset;
	$tree->charset($cs||'iso-8859-1');

	$tree->write(defined $cs ? decode $cs, $src : $src);
	$tree->close;

	# This used to trigger the load event on the body  element  (which
	# conformed to HTML 5 at the time [10 June 2008 draft]),  but which
	# was not fully  compatible  with  any  existing  browser.  HTML  5
	# changed to what Firefox and Safari did  (some time before Septem-
	# ber, 2009),  which is what we now have here.  (It still doesn’t
	# quite make sense, as the document is not actually the target.)
	$self->trigger_event('load', target => $tree);

	# banana
	$self->{form} = ($self->{forms} = $tree->forms)->[0];

	return;
}

# Not an override, but used by update_html
sub _handler_for_lang {
 my ($self,$lang) = @_;
 if(defined $lang) {
     while(my($lang_re,$handler) = each
          %{$script_handlers{$self}}) {
        next if $lang_re eq 'default';
        $lang =~ $lang_re and
            # reset iterator:
            keys %{$script_handlers{$self}},
            return $handler;
     }
 }
 return $script_handlers{$self}{default} || ();
}

# Not an override, but used by update_html
sub _line_no {
	my ($src,$offset) = @_;
	return 1 + (() =
		substr($src,0,$offset)
		    =~ /\cm\cj?|[\cj\x{2028}\x{2029}]/g
	);
}

# ~~~ This ends up creating a new WSL object every time we come back to the
#     same page. We need a way to make this more efficient. The same goes
#     for images.
sub _extract_links {
	tie my @links, WWW'Scripter'Links:: =>
		scalar +(my $self = shift)->document->links;
	# banana
	$self->{links} = \@links;
	$self->{_extracted_links} = 1;

	return;
}

sub _extract_images {
	my $doc = (my $self= shift)->document;
	my $list = HTML::DOM::NodeList::Magic->new(
	    sub { grep tag $_ =~ /^i(?:mg|nput)\z/,
		$doc->descendants },
	    $doc
	);
	tie my @images, WWW'Scripter'Images:: => $list;

	# banana
	$self->{images} = \@images;
	$self->{_extracted_images} = 1;

	return;
}

sub back {
   shift->{page_stack}->go(-1)
}

# ------------- Window interface ------------- #

# This does not follow the same format as %HTML::DOM::Interface; this cor-
# responds to the format of hashes *within* %H:D:I. The other format does
# not apply here, since we can’t bind the class like other classes. This
# needs to be bound to the global  object  (at  least  in  JavaScript).
our %WindowInterface = (
	%{$HTML::DOM::Interface{AbstractView}},
	%{$HTML::DOM::Interface{EventTarget}},
	alert => VOID|METHOD,
	confirm => BOOL|METHOD,
	prompt => STR|METHOD,
	location => OBJ,
	setTimeout => NUM|METHOD,
	clearTimeout => NUM|METHOD,
	open => OBJ|METHOD,
	window => OBJ|READONLY,
	self => OBJ|READONLY,
	navigator => OBJ|READONLY,
	top => OBJ|READONLY,
	frames => OBJ|READONLY,
	length => NUM|READONLY,
	parent => OBJ|READONLY,
);

sub alert {
	my $self = shift;
	&{$$self{Scripter_alert}||sub{print @_,"\n";()}}(@_);
}
sub confirm {
	my $self = shift;
	($$self{Scripter_confirm}||$self->die(
		"There is no default confirm function"
	 ))->(@_)
}
sub prompt {
	my $self = shift;
	($$self{Scripter_prompt}||$self->die(
		"There is no default prompt function"
	 ))->(@_)
}

sub location {
	my $self = shift;
	my $loc = $self->{Scripter_loc} ||= WWW::Scripter::Location->new(
	 $self
	);
	$loc->href(@_) if @_;
	$loc;
}

sub navigator {
	my $self = shift;
	$navi{$self} ||=
		new WWW::Scripter::Navigator:: $self;
}

sub setTimeout {
	my $doc = shift->document;
	my $time = time;
	my ($code, $ms) = @_;
	$ms /= 1000;
	my $t_o = $timeouts{$doc}||=[];
	$$t_o[my $id = @$t_o] =
		[$ms+$time, $code];
	return $id;
}

sub clearTimeout {
	delete $timeouts{shift->document}[shift];
	return;
}

sub open {
	shift->get(shift);
			# ~~~ Just a placeholder for now.
	return;
}



sub history { $_[0]{page_stack} }

sub frames {
 my $doc = $_[0]->document;
 my $frames = $frames{$doc||''}         # the ||'' is for non-HTML docu-
  ||= WWW::Scripter'Frames->new( $_[0], $doc );  # ments, which all share
 wantarray ? @$frames : $frames                          # an empty frames
}                                                              # collection

sub window { $_[0] }
*self = *window;
sub length { $frames{$_[0]->document}->length }

sub top {
	my $self = shift;
	$top{$self} || do {
		my $parent = $self;
		while() {
			$parent{$parent} or
			 weaken( $top{$self} = $parent), last;
			$parent = $parent{$parent};
		}
		$top{$self}
	};
}

sub parent {
	my $self = shift;
	$parent{$self} || $self;
}

sub _set_parent { weaken( $parent{$_[0]} = $_[1] ) }

# ------------- Window-Related Public Methods -------------- #

sub set_alert_function   { ${$_[0]}{Scripter_alert}     = $_[1]; }
sub set_confirm_function { ${$_[0]}{Scripter_confirm} = $_[1]; }
sub set_prompt_function  { ${$_[0]}{Scripter_prompt} = $_[1]; }

sub check_timers {
	my $time = time;
	my $self = shift;
	local *_;
	my $t_o = $timeouts{$self->document}||return;
	for my $id(0..$#$t_o) {
		next unless $_ = $$t_o[$id];
		$$_[0] <= $time and
			($self->_handler_for_lang('JavaScript')||return)
				->eval($self,$$_[1]),
#			$@ && $self->warn($@),
# ~~~ need to fix an HTML::DOM bug before we can warn here
#     should we be warning at all?
			delete $$t_o[$id];
	}
	return
}

sub count_timers {
 	my $self =  shift;
	my $t_o = $timeouts{$self->document}||return 0;
	my $count;
	for my $id(0..$#$t_o) {
		next unless $_ = $$t_o[$id];
		++$count
	}
	$count;
}

# ------------- EventTarget interface ------------- #

{
 package WWW::Scripter::EventTarget;
 use Scalar'Util 'weaken';
 our @ISA = HTML'DOM'EventTarget::;
 sub new { my $self = bless \(my $dummy = pop);  weaken $$self; $self }
 sub event_listeners_enabled { ${$_[0]}->scripts_enabled }
}

sub AUTOLOAD {
	my($pack,$meth) = our $AUTOLOAD =~ /(.*)::(.*)/s;
	return if $meth eq 'DESTROY';
	$meth =~ /^on([a-z]+)\z/
		or die "Can't locate object method \"$meth\" via package "
			."$pack at ".join' line ',(caller)[1,2]
			,. "\n";
	my $self = shift;
	(
	 $evtg{$self->response}
	  ||= new WWW'Scripter::EventTarget $self
	)->attr_event_listener($1, @_);
}
# ~~~ Is there any fairly reliable and efficient way to get this list auto-
#     matically? We only want methods, not utility functions like
#     _dispatch_event.
for my $meth (qw b addEventListener removeEventListener attr_event_listener
                   get_event_listeners dispatchEvent trigger_event b) {
 no strict 'refs';
 *$meth = sub {
   my $self = shift;
   (
    $evtg{$self->response} ||= new WWW'Scripter'EventTarget:: $self
   )->$meth(@_)
  }
}


# ------------- Scripting hooks and what-not ------------- #

sub eval {
 my ($self,$code) = (shift,shift);
 my $h = $self->_handler_for_lang(my $lang = shift);
 my $ret = (
  $h or $self->die(
   defined $lang ? "No scripting handlers have been registered for $lang"
                 : "No scripting handlers have been registered"
  )
 )->eval($self,$code);
 $@ and $self->warn($@);
 $ret;
}

sub use_plugin {
    my ($self, $plugin, @opts) = (shift, shift, @_);
    my $plugins = $self->{plugins} ||= {};
    $plugin = _plugin2module($plugin);
    return $plugins->{$plugin} if $self->{cloning};
    if(exists $plugins->{$plugin}) {
        $plugins->{$plugin}->options(@opts) if @opts;
    }
    else {
        (my $plugin_file = $plugin) =~ s-::-/-g;
        require "$plugin_file.pm";
        $plugins->{$plugin} = $plugin->init($self, \@opts);
        $plugins->{$plugin}->options(@opts) if @opts;
    }
    $plugins->{$plugin};
}

sub plugin {
    my $self = shift;
    my $plugin = _plugin2module(shift);
    return exists $self->{plugins}{$plugin}
        ? $self->{plugins}{$plugin} || 1 : 0;
}

sub _plugin2module { # This is NOT a method
    my $name = shift;
    return $name if $name =~ /::/;
    $name =~ s/-/::/g;
    return __PACKAGE__."::Plugin::$name";
}

sub _clone_plugins {
    my $self = shift;
    return unless $self->{plugins};
    my $plugins = $self->{plugins} = { %{$self->{plugins}} };
    while ( my($pn,$po) = each %$plugins ) {
            # plugin name, plugin object
        next unless $po && defined blessed $po && $po->can('clone');
        $plugins->{$pn} = $po->clone($self);
    }
}

sub scripts_enabled {
	my $old = $scriptable{my $self = shift};
	defined $old or $old = 1; # default
	if(@_) {{
	  $scriptable{$self} = !!$_[0]; # We don’t want undef resetting it.
	  ($self->document ||last) ->event_listeners_enabled(shift) ;
	}}
	$old
}
# used by HTML::DOM::EventTarget:
*event_listeners_enabled = *scripts_enabled; 

sub script_handler {
	my($self,$key) = (shift,shift);
	my $old = $script_handlers{$self}{$key};
	@_ and $script_handlers{$self}{$key} = shift;
	$old
}

sub class_info {
	my $self = shift;
	@_ and push @{ $class_info{$self} }, shift;
	@{ $class_info{$self} } if defined wantarray;
}

# ------------- Miss Elaine E. S. ------------- #

# This function is exported upon request.
sub abort {
    no warnings 'exiting';
    last Scripter_ABORT;
}

sub forward {
    my $self = shift;
    $self->{page_stack}->go(1);
}

sub clear_history {
    my $self = shift;
    $$self{'page_stack'}->_clear(@_);
    if (shift) {
        $self->_reset_page;

        # list of keys taken from _update_page
        delete $self->{$_} for qw[ req redirected_url res status base ct
            uri last_uri content ];
        _initial_page($self);
    }
    return $self;
}

sub max_docs {
 my $self= shift;
 defined wantarray and my $old = $self->stack_depth+1;
 $self->stack_depth(shift()-1) if @_;
 $old;
}

sub max_history {
 my $old = (my $self = shift)->{Scripter_max_hist};
 @_ and $self->{Scripter_max_hist} = shift;
 $old
}

# ------------- History object ------------- #

package WWW::Scripter::History;

<<'mldistwatch' if 0;
use WWW::Scripter; $VERSION = $WWW'Scripter'VERSION;
mldistwatch
our $VERSION = $WWW'Scripter'VERSION;

use Hash::Util::FieldHash::Compat 'fieldhashes';
use HTML::DOM::Interface qw 'NUM STR READONLY METHOD VOID';
use Scalar::Util 'weaken';

=begin comment

History notes

A history object is a blessed array ref. That array ref holds the browser
history entries. Each entry is itself an array ref containing:

0 - request object
1 - response object
2 - URL
3 - state info
4 - title

The length of the array tells us whether it is a state-info entry. The URL
is used both for fragments and for state objects. The second element will
be blank if it has been erased because of max_docs.

The history object has a pointer to the ‘current’ history item
($index{$self}).

Document objects are referenced by response: $document{$response}. The
‘document’ method is inherited from HTML::DOM::View, and we set it whenever
history is browsed, retrieving it from %document.

The ‘unbrowsed’ state mentioned in HTML 5 is represented by an empty array.

Response objects are also listed in the array ref stored in $res{$self} in
the order in which they were accessed. Subroutines that add to this array
then call  _clean($self),  which then eliminates duplicate entries  and
deletes from the history object itself as many of the oldest response
objects as are necessary to satisfy max_docs.

=end comment

=cut

$$_{~~__PACKAGE__} = 'History',
$$_{History} = {
	length => NUM|READONLY,
	index => NUM|READONLY,
	userAgent => STR|READONLY,
	go => METHOD|VOID,
	back => METHOD|VOID,
	forward => METHOD|VOID,
	pushState => METHOD|VOID,
}
for \%WWW::Scripter::Interface;

fieldhashes \my ( %w, %index, %res );

sub new {
	my ($pack,$mech) = @_;
	my $self = bless [[]], $pack;
	weaken($w{$self} = $mech);
	$index{$self} = 0;
	$res{$self} = [];
	$self
}

sub _add {
 my $self = shift;
 if(defined $$self[-1][0]) { # if there is no ‘undef’ entry
  splice @$self, ++$index{$self};
  push @$self, \@_;
  push @{$res{$self}}, $_[1]; 
  _clean($self,1);
 }
 else {
  $$self[-1] = \@_;
  push @{$res{$self}}, $_[1];
 }
}

# Called when browsing to a stale history entry and also by
# location->replace
sub _replace {
 my $self = shift;
 if(defined $$self[-1][0]) { # if browsing has occurred
  $$self[$index{$self}] = \@_;
  push @{$res{$self}}, $_[1]; 
  _clean($self);
 }
 else {
  $$self[-1] = \@_;
  push @{$res{$self}}, $_[1];
 }
}

sub _delete_res {
 delete $_[0][$index{$_[0]}][1];
}

sub _clear { # called by Scripter->clear_history
	my $self = shift;
	@$self = shift() ? undef : $$self[$index{$self}];
	$index{$self} = 0;
}

sub length {
    scalar @{+shift}
}

sub index { # ~~~ We can probably make this modifiable later.
 $index{+shift}
}

sub go {
 my $self = shift;
 if(!$_[0]) {
  $w{$self}->reload;
 }
 else {
  my $new_pos = $index{$self}+shift;
  $new_pos < 0 || $new_pos > $#$self and return;
  $index{$self} = $new_pos;

  # ~~~ trigger popstate

  # If there is a response object, we just reset the page from that. If
  # there isn’t then this is a stale entry and we need to
  # re-fetch the page.
  my $entry = $$self[$new_pos];
  if(defined $$entry[1]) { # response
   $w{$self}->_update_page(@$entry)
  }
  else {
   local(my $w = $w{$self})->{Scripter_replace} = 1;
   $w->request($$entry[0]);
  }
 }
 return;
}

sub back { shift->go(-1) }
sub forward { shift->go(1) }

sub pushState {
 my $self = shift;

 my $index = $index{$self}++;
 my($req,$res) = @{$$self[$index]}[0,1];

 # count future entries that share the same doc
 my $to_delete;
 for($index+1..$#$self) {
  ($$self[$_][1]||0) == $res ? ++$to_delete : last;
 }

 # replace those future entries with the new item
 splice @$self, $index+1, $to_delete||0, [ $req, $res, $_[2], @_ ];

 _clean($self);

 return;
}

sub _clean {
 my($self, $check_max_hist) = @_;
 if($check_max_hist) {
  my $max = (my $w = $w{$self})->{Scripter_max_hist};
  if($max && @$self > $max) {
   my $diff = @$self-$max;
   $index{$self} -= $diff;
   splice @$self, 0, $diff;
  }
 }
 my $max = $w{$self}->stack_depth + 1;
 my $res = $res{$self};
 my %res;
 for(@$self) {
  defined $$_[1] and $res{0+$$_[1]}++
 }
 if($max) { # ~~~ It may be more efficient if, instead of searching for
  my @res;  #     duplicates here, we scan for the ones we know we’ve added
  my %seen; #     in _add and _replace.
  for(reverse @$res) {
   my $refaddr = 0+$_;
   unshift @res, $_ if exists $res{$refaddr} && !$seen{$refaddr}++;
  }
  @$res = @res, return unless @res > $max;
  my $diff = @res-$max;
  my %to_delete;
  @to_delete{map 0+$_, splice @res, 0,$diff}=();
  @$res = @res;
  for(@$self) {
   next unless defined $$_[1];
   delete $$_[1] if exists $to_delete{0+$$_[1]};
  }
 }
 else {
  @$res = grep exists $res{refaddr $_}, @$res;
 }
}

sub _uri {
 my $self = shift;
 $$self[$index{$self}][2] || $w{$self}->uri;
}

# ~~~

# ------------- Location object ------------- #

package WWW'Scripter'Location;

<<'mldistwatch' if 0;
use WWW::Scripter; $VERSION = $WWW'Scripter'VERSION;
mldistwatch
our $VERSION = $WWW'Scripter'VERSION;

use URI;
use HTML::DOM::Interface qw'STR METHOD VOID';
use Scalar::Util 'weaken';

use overload fallback => 1, '""' => sub{${+shift}->history->_uri};

$$_{~~__PACKAGE__} = 'Location',
$$_{Location} = {
	hash => STR,
	host => STR,
	hostname => STR,
	href => STR,
	pathname => STR,
	port => STR,
	protocol => STR,
	search => STR,
	reload => VOID|METHOD,
	replace => VOID|METHOD,
}
for \%WWW::Scripter::Interface;

sub new { # usage: new .....::Location $mech
	my $class = shift;
	weaken (my $mech = shift);
	my $self = bless \$mech, $class;
	$self;
}

sub hash {
	my $loc = shift;
	my $old = (my $uri = $$loc->history->_uri)->fragment;
	$old = "#$old" if defined $old;
	if (@_){
		shift() =~ /#?(.*)/s;
		(my $uri_copy = $uri->clone)->fragment($1);
		$uri_copy->eq($uri) or $$loc->get($uri_copy);
	}
	$old||''
}

sub host {
	my $loc = shift;
	my $uri = $$loc->history->_uri;
	if (@_) {
		(my $uri = $uri->clone)->port("");
		$uri->host_port(shift);
		$$loc->get($uri);
	}
	defined wantarray ? $uri->host_port : ()
}

sub hostname {
	my $loc = shift;
	my $uri = $$loc->history->_uri;
	if (@_) {
		(my $uri = $uri->clone)->host(shift);
		$$loc->get($uri);
	}
	defined wantarray ? $uri->host : ()
}

sub href {
	my $loc = shift;
	my $old = $$loc->history->_uri->as_string if defined wantarray;
	if (@_) {
		$$loc->get(shift);
	}
	$old;
}

sub pathname {
	my $loc = shift;
	my $uri = $$loc->history->_uri;
	if (@_) {
		(my $uri = $uri->clone)->path(shift);
		$$loc->get($uri);
	}
	defined wantarray ? $uri->path : ()
}

sub port {
	my $loc = shift;
	my $uri = $$loc->history->_uri;
	if (@_) {
		(my $uri = $uri->clone)->port(shift);
		$$loc->get($uri);
	}
	defined wantarray ? $uri->port : ()
}

sub protocol {
	my $loc = shift;
	my $uri = $$loc->history->_uri;
	if (@_) {
		shift() =~ /(.*):?/s;
		(my $uri = $uri->clone)->scheme($1);
		$$loc->get($uri);
	}
	defined wantarray ? $uri->scheme . ':' : ()
}

sub search {
	my $loc = shift;
	my $uri = $$loc->history->_uri;
	if (@_){
		shift() =~ /(\??)(.*)/s;
		(
		 my $uri_copy = $uri->clone
		)->query(
			$1||length$2 ? "$2" : undef
		);
		$$loc->get($uri_copy);
	}
	return unless defined wantarray;
	my $q = $uri->query;
	defined $q ? "?$q" : "";
}


# ~~~ Safari doesn't support forceGet. Do I need to?
sub reload  { # args (forceGet) 
	${+shift}->reload
}
sub replace { # args (URL)
	my $mech = ${+shift};
	local $$mech{Scripter_replace } = 1;
	$mech->get(shift);
}


# ------------- Navigator object ------------- #

package WWW::Scripter::Navigator;

use HTML::DOM::Interface qw'STR READONLY';
use Scalar::Util 'weaken';

<<'mldistwatch' if 0;
use WWW::Scripter; $VERSION = $WWW'Scripter'VERSION;
mldistwatch
our $VERSION = $WWW'Scripter'VERSION;

$$_{~~__PACKAGE__} = 'Navigator',
$$_{Navigator} = {
	appName => STR|READONLY,
	appVersion => STR|READONLY,
	userAgent => STR|READONLY,
}
for \%WWW::Scripter::Interface;

no constant 1.03 ();
use constant::lexical {
	mech => 0,
	name => 1,
	vers => 2,
};

sub new {
	weaken((my $self = bless[],pop)->[mech] = pop);
	$self;
}

sub appName {
	my $self = shift;
	my $old = $self->[name];
	defined $old or $old = ref $self->[mech];
	@_ and $self->[name] = shift;
	return $old;
}

sub appVersion {
	my $self = shift;
	my $old = $self->[vers];
	if(!defined $old) {
		$old = $self->userAgent;
		$old =~ /(\d.*)/s
		? $old = $1
		: $old = ref($self->[mech])->VERSION;
	}
	@_ and $self->[vers] = shift;
	return $old;
}

sub userAgent {
	shift->[mech]->agent;
}

# ------------- about: protocol ------------- #

package WWW'Scripter'_about_protocol;

# ~~~ This method may be a bad idea if someone else wants to implement
#     other aspects of the about: protocol. Maybe we should use an LWP
#     handler. (Then we would, of course, require a later LWP.)

<<'mldistwatch' if 0;
use WWW::Scripter; $VERSION = $WWW'Scripter'VERSION;
mldistwatch
our $VERSION = $WWW'Scripter'VERSION;

use LWP::Protocol;

our @ISA = LWP::Protocol::;

LWP::Protocol'implementor about => __PACKAGE__;

sub request { # based on the one in LWP::Protocol::file
	my($self, $request, $proxy, $arg) = @_;

	if(defined $proxy) {
		return new HTTP::Response 400,,
			'The about: protocol does not work with proxies';
	}

	my $url=  $request->url;
	my $scheme = $url->scheme;	

	if ($scheme ne 'about') {
		return new HTTP::Response 500,
		    "WWW::Scripter::_about_protocol called for $scheme";
	}

	return new HTTP::Response 404,
		"Nothing exists at $url" unless $url eq 'about:blank';

	my $response = new HTTP::Response 200, 'OK', [
		Content_Length=>0,
		Content_Type  =>'text/html',
	];

	$self->collect($arg, $response, sub {\''});
}

# ------------- Link and image lists for Mech ------------- #

package WWW::Scripter::Links;

<<'mldistwatch' if 0;
use WWW::Scripter; $VERSION = $WWW'Scripter'VERSION;
mldistwatch
our $VERSION = $WWW'Scripter'VERSION;

use WWW::Mechanize::Link;

sub TIEARRAY {
	bless \(my $links = pop), shift;
}

sub FETCH     {
	my $link = ${$_[0]}->[$_[1]];
	my $mech_link = new WWW'Mechanize'Link::{
		url => $link->attr('href'),
		text => $link->as_text,
		name => $link->attr('name'),
		tag => $link->tag,
		base => $link->ownerDocument->base,
		attrs => {$link->all_external_attr},
	};
	$dom_obj{$mech_link} = $link;
	$mech_link;
}
sub FETCHSIZE { scalar @${$_[0]} }
sub EXISTS    { exists ${$_[0]}->links->[$_[1]] }


package WWW::Scripter::Images;

<<'mldistwatch' if 0;
use WWW::Scripter; $VERSION = $WWW'Scripter'VERSION;
mldistwatch
our $VERSION = $WWW'Scripter'VERSION;

use WWW::Mechanize::Image;

sub TIEARRAY {
	bless \(my $links = pop), shift;
}

sub FETCH     {
	my $img = ${$_[0]}->[$_[1]];
	my $mech_img = new WWW'Mechanize'Image::{
		url => $img->attr('src'),
		name => $img->attr('name'),
		tag => $img->tag,
		base => $img->ownerDocument->base,
		height => $img->attr('height'),
		width => $img->attr('width'),
		alt => $img->attr('alt'),
	};
	$dom_obj{$mech_img} = $img;
	$mech_img;
}
sub FETCHSIZE { scalar @${$_[0]} }
sub EXISTS    { exists ${$_[0]}->links->[$_[1]] }


# ------------- Frames list ------------- #

package WWW::Scripter::Frames;

<<'mldistwatch' if 0;
use WWW::Scripter; $VERSION = $WWW'Scripter'VERSION;
mldistwatch
our $VERSION = $WWW'Scripter'VERSION;

# ~~~ This is horribly inefficient and clunky. It probably needs to be
#     programmed in full here, or at least the ‘Collection’ part (a tiny
#     bit of copy&paste).

use HTML::DOM::Collection;
use HTML::DOM::NodeList::Magic;
our @ISA = "HTML::DOM::Collection";

{
	Hash'Util'FieldHash'Compat'fieldhash my %w;
	my @empty_array;
	
	sub new {
		; my($pack,$window,$doc) = @_
		; my $ret = $pack->SUPER'new(
		   $doc
		    ? HTML::DOM::NodeList::Magic->new(
		       sub { $doc->look_down(_tag => qr/^i?frame\z/) },
		       $doc
		      )
		    : HTML'DOM'NodeList->new(\@empty_array)
		  )
		; $w{$ret} = $window
		; $ret
	}
	
	sub window { $w{+shift} }
	}

use overload fallback => 1,'@{}' => sub {
	[map $_->contentWindow, @{shift->${\'SUPER::(@{}'}}]
};

sub FETCH { (shift->SUPER::FETCH(@_)||return)->contentWindow }


!!*!*!!*!*!!*!*!!*!*!!*!*!!*!*!!*!*!!*!*!!*!*!!*!*!!*!*!!*!*!!*!*!!*!
