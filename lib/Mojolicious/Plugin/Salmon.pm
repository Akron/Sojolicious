package Mojolicious::Plugin::Salmon;
use strict;
use warnings;
use Mojo::Base 'Mojolicious::Plugin';

has 'host';
has secure => 0;

our ($salmon_ns_replies,
     $salmon_ns_mentioned,
     $me_mime);
BEGIN {
    $salmon_ns_replies   = 'http://salmon-protocol.org/ns/salmon-replies';
    $salmon_ns_mentioned = 'http://salmon-protocol.org/ns/salmon-mention';
    $me_mime             = 'application/magic-envelope';
}

# Register plugin
sub register {
    my ($plugin, $mojo, $param) = @_;


    # Dependencies
    # Load magic signatures if not loaded
    # Automatically loads webfinger and hostmeta and endpoint and xrd.
    unless (exists $mojo->renderer->helpers->{'magicenvelope'}) {
	$mojo->plugin('MagicSignatures', {'host' => $param->{'host'}} );
    };

    # Attributes
    # set host
    if (defined $param->{host}) {
	$plugin->host($param->{host});
    } else {
	$plugin->host( $mojo->hostmeta('host') || 'localhost' );
    };

    # Does it need ssl or not
    $plugin->secure( $param->{secure} );

    # Shortcuts
    # Add 'salmon' shortcut
    $mojo->routes->add_shortcut(
	'salmon' => sub {
	    my ($route, $param) = @_;
	    
	    # Todo: Mojo-Debug
	    warn 'Unknown Salmon parameter' && return
		unless $param =~ /^(?:mentioned|all-replies|signer)$/;
	    
	    
	    # Handle GET requests
	    $route->get->to(
		'cb' => sub {
		    return shift->render(
			'template'       => 'salmon-endpoint',
			'template_class' => __PACKAGE__,
			'status'         => 400 # bad request
			);
		});

	    # Set salmon endpoints
	    $route->endpoint(
		'salmon-'.$param,
		{ scheme => $plugin->secure ? 'https' : 'http',
		  host   => $plugin->host }
		);
	    
	    if ($param eq 'all-replies') {
		
		# Add reply handle to webfinger
		$mojo->hook(
		    'before_serving_webfinger' => sub {
			my ($c, $acct, $xrd) = @_;
			
			$xrd->add_link(
			    $salmon_ns_replies,
			    { 'href' => $c->get_endpoint('salmon-all-replies') }
			    )->comment('Salmon Reply Endpoint');
		    
		    });
		
		# Handle POST requests
		$route->post->to(
		    'cb' => sub { $plugin->_all_replies( @_ ) }
		    );

	    }

	    # Mention route
	    elsif ($param eq 'mentioned') {

		# Add mention handle to webfinger
		$mojo->hook(
		    'before_serving_webfinger' => sub {
			my ($c, $acct, $xrd) = @_;

			$xrd->add_link(
			    $salmon_ns_mentioned,
			    { 'href' => $c->get_endpoint('salmon-mentioned') }
			    )->comment('Salmon Mentioned Endpoint');

		    });

		# Handle POST requests
		$route->post->to(
		    'cb' => sub { $plugin->_mentioned( @_ ) }
		    );
	    }
	    
	    # Signer route
	    elsif ($param eq 'signer') {
		
		# Todo: Fragen: Gibt es schon eine Signer-URI?
		my $salmon_signer_url = $mojo->endpoint('salmon-signer');
		
		# Add signer link to host-meta
		my $link = $mojo->hostmeta->add_link(
		    'salmon-signer',
		    { href => $salmon_signer_url }
		    );
		$link->comment('Salmon Signer Endpoint');
		$link->add('Title', 'Salmon Endpoint');


		$route->post->to(
		    'cb' => sub { $plugin->_signer( @_ ); }
		    );
	    };
	});
    # Helpers?
};

sub salmon {
    my $plugin = shift;
    my $c = shift;

    my $content_type = $c->req->headers->content_type;

    if (index($content_type, $me_mime) == 0) {
        my ($unwrapped_content_type,
	    $unwrapped_body) =
		$c->magicenvelope($c->req->body)->data;

	# Use Atom information
	# elsif ($me->data_type eq 'application/atom+xml') {
	#  my $entry = $me->data->dom->at('entry');
	#	return unless $entry;
	#	
	#	my $author = $entry->at('author uri');
	#	return unless $author;
	#	
	#	$acct = $author->text || undef;
	# };


	$c->respond_to(
	    'me+xml'  => { text =>
			       'XML: '.
			       $unwrapped_content_type.
			       "\n\n".
			       $unwrapped_body },
	    'me+json' => { text =>
			       'JSON: '.
			       $unwrapped_content_type.
			       "\n\n".
			       $unwrapped_body}
	    );
    }

    # No magic envelope
    else {
	$c->render_text('Booh! No me!');
    };
};

# to be implemented!
sub _signer {
    my $plugin = shift;

    warn 'Salmon signer is not yet implemented.';

    my $c = shift;

    # Check OAuth token
    # 401 if not correct
    # ...

# Hook before_salmon_sign
# Hook after_salmon_sign

    my $body = $c->req->body;
    my $data_type = $c->req->headers->header('Content-Type');

    my %me_data = ( data => $body );
    $me_data{data_type} = $data_type if $data_type;

    my $me = $c->magicenvelope(\%me_data);

    warn 'ME is empty.' unless $me;

    # Retrieve based on oauth
    my $mkey = 'RSA.'.
    'mVgY8RN6URBTstndvmUUPb4UZTdwvw'.
    'mddSKE5z_jvKUEK6yk1u3rrC9yN8k6'.
    'FilGj9K0eeUPe2hf4Pj-5CmHww==.'.
    'AQAB.'.
    'Lgy_yL3hsLBngkFdDw1Jy9TmSRMiH6'.
    'yihYetQ8jy-jZXdsZXd8V5ub3kuBHH'.
    'k4M39i3TduIkcrjcsiWQb77D8Q==';

    # Sign magic envelope
    $me->sign( { key => $mkey } );

    return $plugin->_render_me($c,$me);
};

sub _all_replies {
    my $c = shift;
    
    my $req = $c->req;
	    
    # Verify OAuth
    # 401 if not correct
    # Or 202 for later verification
    
    # Verify MagicSignature
    # 400 if not correct
    if ($req->body) {
	my $me = $c->magicenvelope($req->body);
	unless ($me) {
	    return $c->render(
		status   => 400,
		template => 'salmon',
		title    => 'Salmon Error',
		content  => 'The posted magic '.
		'envelope seems '.
		'to be empty.',
		template_class => __PACKAGE__
		);
	};
	
	# my $author = $self->_discover_author($me);
	
	# my $verb = $c->activity($me)->verb;
	
	$c->app->plugins->run_hook( 'before_salmon_reply_verification'
				    => $c, $me);
	
	# verification
	
	# Ceck Timestamp
	# 400 if not valid

	# Further Checks. Via hook.
			    
	$c->app->plugins->run_hook( 'on_salmon_reply'
				    => $c, $me);

	unless ($c->rendered) {
	    $c->render(
		status => 200,
		template => 'salmon-reply-ok',
		template_class => __PACKAGE__
		);
	};
	
	return;

    } else {
	return $c->render(
	    status   => 400,
	    template => 'salmon',
	    title    => 'Salmon Error',
	    content  => 'The posted magic '.
	    'envelope seems '.
	    'to be empty.',
	    template_class => __PACKAGE__
	    );
    };
};


sub _mentioned {
    my $c = shift;

    my $req = $c->req;

    if ($req->body) {
	my $me = $c->magicenvelope($req->body);
	unless ($me) {
	    return $c->render(
		status   => 400,
		template => 'salmon',
		title    => 'Salmon Error',
		content  => 'The posted magic '.
		'envelope seems '.
		'to be empty.',
		template_class => __PACKAGE__
		);
	};
	
	$c->app->plugins->run_hook( 'before_salmon_mention_verification'
				    => $c, $me);
	
	
	# my $author = $self->discover_author($me);
	
	$c->app->plugins->run_hook( 'on_salmon_mention'
				    => $c, $me);

	unless ($c->rendered) {
	    $c->render(
		status => 200,
		template => 'salmon-mentioned-ok',
		template_class => __PACKAGE__
		);
	};

    } else {
	return $c->render(
	    status   => 400,
	    template => 'salmon',
	    title    => 'Salmon Error',
	    content  => 'The posted magic '.
	    'envelope seems '.
	    'to be empty.',
	    template_class => __PACKAGE__
	    );
    };
};

sub _discover_author {
    my $plugin = shift;
    my $me = shift;
    
    if (my $dom = $me->dom) {
	my $uri = $dom->at('author uri')->text;
	return unless $uri;
	
	my $webfinger = $plugin->app->webfinger($uri);
	my $author_key = $webfinger->dom->at('magic-key'); #???
    };

    return;
};

# Render according to the accepted format
sub _render_me {
    my $plugin = shift;
    my $c = shift;
    my $me = shift;

    my $accept = $c->req->headers->header('Accept');

    unless ($accept) {
	return $c->render(
	    'format' => 'me-xml',
	    'data'   => $me->to_xml
	    );
    } else {

	# Check, which format should be delivered
	foreach my $type ( _accept( $accept ) ) {

	    # Accept xml
	    if ($type =~ m{(?:xml|/\*$)}) {
		return $c->render(
		    'format' => 'me-xml',
		    'data'   => $me->to_xml
		    );
	    }

	    # Accept json
	    elsif ($type =~ m{json}) {
		return $c->render(
		    'format' => 'me-json',
		    'data'   => $me->to_json
		    );
	    }

	    # Accept compact format
	    elsif ($type =~ m{(?:text|compact)}) {
		return $c->render(
		    'format' => 'me-compact',
		    'data'   => $me->to_compact
		    );
	    };
	};

    };

    # The accepted format cannot be delivered.
    return $c->render(
	'format' => 'text/plain',
	'status' => 406,
	'data' => q{The requested Content-Type can not be delivered.}
	);
};

# Sort by accept string
sub _accept {
    my $accept = shift;

    my @accept_new;

    foreach (split(/\s*,\s*/, $accept)) {
	my @content_type = split(/\s*;\s*/, $_ );
	my %accept_v = (
	    type => shift(@content_type)
	    );
	foreach (@content_type) {
	    my ($k, $v) = split(/\s*=\s*/, $_);
	    $accept_v{$k} = $v;
	};
	unless ($accept_v{q}) {
	    $accept_v{q} = 1;
	};
	push(@accept_new, \%accept_v);
    };

    return (
	map( $_->{type},
	     sort { $a->{q} <=> $b->{q} } @accept_new
	));
};


1;

__DATA__
@@ layouts/salmon.html.ep
<!doctype html>
<html>
  <head>
    <title><%= $title %></title>
  </head>
  <body>
    <h1><%= $title %></h1>
    <%== content %>
  </body>
</html>

@@ salmon-endpoint.html.ep
% layout 'salmon', title => 'Salmon Endpoint';
    <p>
      This is an endpoint for the
      <a href="http://salmon-protocol.googlecode.com/svn/trunk/draft-panzer-salmon-00.html">Salmon protocol</a>
    </p>
    <p>
      There is no reason to <emph>get</emph>
      this ressource.
      However - feel free to <emph>post</emph>!
    </p>

@@ salmon-reply-ok.html.ep
% layout 'salmon', title => 'Salmon'
   <p>Thank you for your reply.</p

@@ salmon-mentioned-ok.html.ep
% layout 'salmon', title => 'Salmon'
   <p>Thank you for your mention.</p

__END__

=pod

=head1 NAME

Mojolicious::Plugin::Salmon - A Salmon Plugin for Mojolicious

=head1 SYNOPSIS

  use Mojolicious::Lite;

  plugin 'Salmon', host => 'example.org';

  my $r = app->routes;

  my $salmon = $r->route('/salmon');
  $salmon->route('/:user/mentioned')->salmon('mentioned');
  $salmon->route('/:user/all-replies')->salmon('all-replies');
  $salmon->route('/signer')->salmon('signer');

  app->start;

=head1 DESCRIPTION

L<Mojolicious::Plugin::Salmon> is a plugin for L<Mojolicious>
to work with Salmon as described in L<http://salmon-protocol.googlecode.com/svn/trunk/draft-panzer-salmon-00.html|Specification>.

=head1 ATTRIBUTES

=head2 C<host>

  $salmon->host('sojolicio.us');
  my $host = $salmon->host;

The host for the salmon domain.

=head2 C<secure>

  $salmon->secure(1);
  my $sec = $salmon->secure;

Use C<http> or C<https>.

=head1 SHORTCUTS

L<Mojolicious::Plugin::Salmon> provides a shortcut for the "mentioned",
the "all-replies" and the "signer" endpoints as described in
L<http://salmon-protocol.googlecode.com/svn/trunk/draft-panzer-salmon-00.html|Specification>.

  app->routes->route('/:user/mentioned')->salmon('mentioned');

Establishes the mentioned endpoint.

  app->routes->route('/:user/all-replies')->salmon('mentioned');

Establishes the endpoint for all replies to a feed.

  app->routes->route('/signer')->salmon('signer');

Establishes the endpoint for folding and signing a magic envelope
as described in L<http://salmon-protocol.googlecode.com/svn/trunk/draft-panzer-magicsig-01.html|Specification>.
The Client has to authenticate via OAuth as described in
L<http://salmon-protocol.googlecode.com/svn/trunk/draft-panzer-salmon-00.html|Specification>.
The Magic Envelope is - based on the accept header of the request -
in XML format, in JSON format, or Compact notation
(see L<Mojolicious::MagicEnvelope>).

When set, there are three named routes to access in templates:

   print $c->url_for('salmon-mentioned', user => 'bender');
   print $c->url_for('salmon-all-replies', user => 'fry');
   print $c->url_for('salmon-signer');

These can be used for example in HTML C<Link> headers.

=head1 METHODS

=head1 HOOKS

L<Mojolicious::Plugin::Salmon> runs several hooks.
Some are expansible. B<These hooks will be deleted
and exchanged to activity streams based hooks.>

=over 2

=item C<before_salmon_reply_verification>

This hook is run before a salmon-reply is verified.
As verification is computationally expensive, this can
be used for spam protection by white and black listing.
The hook returns the current ??? object and the magic envelope.

B<This hook will in future return the ??? object and the activity
stream entry object.>

=item C<on_salmon_reply>

This hook is run when a verified salmon reply is posted.
The hook returns the current ??? object and the magic envelope.

B<This hook will in future return the ??? object and the activity
stream entry object.>

=item C<before_salmon_mention_verification>

This hook is run before a salmon-mentioned is verified.
As verification is computationally expensive, this can
be used for spam protection by white and black liisting.
The hook returns the current ??? object and the magic envelope.

B<This hook will in future return the ??? object and the activity
stream entry object.>

=item C<on_salmon_mention>

This hook is run when a verified salmon mention is posted.
The hook returns the current ??? object and the magic envelope.

B<This hook will in future return the ??? object and the activity
stream entry object.>

=back

=head1 DEPENDENCIES

L<Mojolicious> (best with SSL support),
L<Mojolicious::Plugin::MagicSignatures>,
L<Mojolicious::Plugin::Webfinger>,
L<Mojolicious::Plugin::HostMeta>.

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2011, Nils Diewald.

This program is free software, you can redistribute it
and/or modify it under the same terms as Perl.

=cut
