package Mojolicious::Plugin::Salmon;
use Mojo::Base 'Mojolicious::Plugin';

# Salmon namespaces
use constant {
  SALMON_REPLIES_NS   => 'http://salmon-protocol.org/ns/salmon-replies',
  SALMON_MENTIONED_NS => 'http://salmon-protocol.org/ns/salmon-mention'
};


# Register plugin
sub register {
  my ($plugin, $mojo, $param) = @_;

  # Push package to render classes for DATA sections
  push (@{ $mojo->renderer->classes }, __PACKAGE__);

  # Load magic signatures if not loaded
  # Automatically loads webfinger, hostmeta, endpoint, and xrd.
  unless (exists $mojo->renderer->helpers->{'magicenvelope'}) {
    $mojo->plugin('MagicSignatures');
  };

  # Add 'salmon' shortcut
  $mojo->routes->add_shortcut(
    salmon => sub {
      my ($route, $param) = @_;

      # Not a valid shortcut parameter
      unless ($param =~ /^(?:mentioned|all-replies|signer)$/) {
	$mojo->log->debug("Unknown Salmon shortcut parameter '$param'");
	return;
      };

      # Handle GET requests
      $route->get->to(
	cb => sub {
	  return shift->render(
	    template => 'salmon-endpoint',
	    status   => 400 # bad request
	  );
	});

      # Set salmon endpoints
      $route->endpoint('salmon-' . $param);

      # All replies route
      # Todo: Both routes can be merged to one
      if ($param eq 'all-replies') {

	# Add reply handle to webfinger
	$mojo->hook(
	  before_serving_webfinger => sub {
	    my ($c, $acct, $xrd) = @_;

	    # Todo: pass acct to endpoint
	    $xrd->add_link(
	      SALMON_REPLIES_NS => {
		'href' => $c->endpoint('salmon-all-replies')
	      })->comment('Salmon Reply Endpoint');
	  });

	# Handle POST requests
	$route->post->to(
	  'cb' => sub { $plugin->_salmon_response( 'reply', @_ ) }
	);
      }

      # Mention route
      elsif ($param eq 'mentioned') {

	# Add mention handle to webfinger
	$mojo->hook(
	  before_serving_webfinger => sub {
	    my ($c, $acct, $xrd) = @_;

	    # Todo: pass acct to endpoint
	    $xrd->add_link(
	      SALMON_MENTIONED_NS => {
		'href' => $c->endpoint('salmon-mentioned')
	      })->comment('Salmon Mentioned Endpoint');

	  });

	# Handle POST requests
	$route->post->to(
	  cb => sub { $plugin->_salmon_response( 'mentioned', @_ ) }
	);
      }

      # Signer route
      elsif ($param eq 'signer') {

	# Todo: Question - is there already a signer URL?

	# Add to hostmeta - exactly once
	$mojo->hook(
	  'on_prepare_hostmeta' =>
	    sub {
	      my ($plugin, $c, $xrd_ref) = @_;
	      my $salmon_signer_url = $c->endpoint('salmon-signer');

	      # Add signer link to host-meta
	      for($xrd_ref->add_link(
		'salmon-signer' => { href => $salmon_signer_url })) {
		$_->comment('Salmon Signer Endpoint');
		$_->add('Title' => 'Salmon Endpoint');
	      };
	    }
	  );

	$route->post->to(
	  cb => sub { $plugin->_signer( @_ ); }
	);
      };
    });

  # Salmon send helper
  $mojo->helper(
    'salmon' => sub {
      return $plugin->salmon_send(@_);
    });
};


# Handle salmon - todo
sub salmon {
  my $plugin = shift;
  my $c = shift;

  my $ct = $c->req->headers->content_type;

  # Content-Type is magic envelope
  if (index($ct, 'application/magic-envelope') == 0) {
    my ($unwrapped_ct, $unwrapped_body) =
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
      'me+xml'  => {
	text => 'XML: ' . $unwrapped_ct . "\n\n" . $unwrapped_body
      },
      'me+json' => {
	text => 'JSON: ' . $unwrapped_ct . "\n\n" . $unwrapped_body
      }
    );
  }

  # No magic envelope
  else {
    return $c->render(
      template => 'salmon-no-me',
      status   => 400 # bad request
    );
  };
};


# To be implemented!
# Needs OAuth token check
sub _signer {
  my $plugin = shift;
  my $c = shift;

  $c->app->debug('Salmon signer is not yet implemented.');
  return;


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

  unless ($me) {
    $c->app->log('Unable to sign MagicEnvelope.');
    return;
  };

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

#  return $plugin->_render_me($c,$me);
  return $c->respond_to(
    'me-json'    => $me->to_json,
    'me-compact' => $me->to_compact,
    'text'       => $me->to_compact,
    'all'        => $me->to_xml
  );
};

sub _salmon_response {
  my $c       = shift;
  my $req     = $c->req;
  my $plugins = $c->app->plugins;

  my $action = 'reply'; # 'mention

  # Verify OAuth
  # 401 if not correct
  # Or 202 for later verification

  # Verify MagicSignature
  # 400 if not correct

  my $me;

  # Magic envelope is not valid
  if (!$req->body || !($me = $c->magicenvelope($req->body))) {

    # Error
    return $c->render(
      status   => 400,
      template => 'salmon',
      title    => 'Salmon Error',
      content  => 'The posted magic ' .
	          'envelope seems ' .
	          'to be empty.'
    )
  };

  # my $author = $self->_discover_author($me);
  # my $verb = $c->activity($me)->verb;

  $plugins->emit_hook(
    'before_salmon_' . $action . '_verification' => ($c, $me)
  );

  # Get authors public keys
  my $public_keys = $c->get_magickeys(
    acct      => 'acct:akron@sojlicio.us', # $user_uri,
    discovery => 0
  );

  # verification
  # Check Timestamp
  #REQUIRED: Check the atom:updated timestamp on the Atom entry against the current server time and the validity period of the signing key. The timestamp SHOULD be no more than one hour behind the current time, and the signing key's validity period MUST cover the atom:updated timestamp. Error code (if provided): 400 Bad Request. The server MAY provide a human readable string in the response body. 

  # Todo: Hook for further checks

  # Verify magic envelope
  if ($me->verify($public_keys)) {

    # Hook on salmon reply
    $plugins->emit_hook(
      'on_salmon_' . $action => ($c, $me)
    );

    unless ($c->rendered) {
      $c->render(
	status         => 200,
	template       => 'salmon-' . $action . '-ok'
      );
    };
    return;
  };

  # Maybe request new magickeys,
  # in case there is a caching error

  # 400 if not verified
  return $c->render(
    status   => 400,
    template => 'salmon',
    title    => 'Salmon Error',
    content  => 'The posted magic ' .
                "envelope can't be validated."
  );
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


# Specific to Sojolicious
sub salmon_send {
  my $plugin = shift;
  my $c      = shift;
  my $entry  = shift;
  my $param  = shift;

  # param: { key_id      => 'key_4', # Todo: Allow multiple signing
  #          send_to     => ['acct:bob@sojolicio.us'],
  #          mentioned   => ['acct:alice@sojolicio.us'],
  #          in_reply_to => 'https://sojolicio.us/blog/1' }

  # The user, who wants to send the salmon
  my $user   = 'acct:akron@sojolicio.us';

  # Get send_to parameter or create
  my @send_to = $param->{send_to} ?
    ( ref($param->{send_to}) eq 'ARRAY' ?
	@{$param->{send_to}} : ($param->{send_to})) : ();

  # Resource of the reply
  if (defined $param->{in_reply_to}) {
    $entry->add_in_reply_to(
      $param->{in_reply_to} => { href => $param->{in_reply_to} }
    );
  };

  # Todo: Discover Salmon endpoints of the mentioned users
  if (exists $param->{mentioned} ) {
    foreach ( @{ $param->{mentioned} } ) {
      $entry->add_link(mentioned => $_);
    };
    push(@send_to, $_ );
  };

  # Add updated timestamp
  $entry->add_updated;

  my $me = $c->magicenvelope({
    data      => $entry->to_pretty_xml,
    data_type => 'application/atom+xml'
  });

  # todo: create provenance

  # Get authors public keys
  # Todo: Allow multiple signin
  my $magickeys = $c->get_magickeys(
    acct      => 'acct:akron@sojlicio.us', # $user_uri,
    key_id    => exists $param->{key_id} ? $param->{key_id} : undef,
    discovery => 0
  );

  # Unable to sign magicenvelope
  if (!$magickeys || !$me->sign( @{ $magickeys->[0] } )) {
    $c->app->log->warn('Unable to sign magicenvelope');
    return;
  };

  # Send magicenvelope
  # Todo: Allow async sending and discovery

  # Todo: discover $param->{in_reply_to}

  foreach my $uri (@send_to) {
    # may be salmon endpoint, maybe lrrd, maybe webfinger
  };
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
      There is no reason to <emph>get</emph> this ressource.
      However - feel free to <emph>post</emph>!
    </p>

@@ salmon-reply-ok.html.ep
% layout 'salmon', title => 'Salmon'
   <p>Thank you for your reply.</p

@@ salmon-mentioned-ok.html.ep
% layout 'salmon', title => 'Salmon'
   <p>Thank you for your mention.</p

@@ salmon-no-me.html.ep
% layout 'salmon', title => 'Salmon Magic Envelope'
   <p>This endpoint expects a magic envelope, see <a href="http://salmon-protocol.googlecode.com/svn/trunk/draft-panzer-salmon-00.html">Salmon protocol</a>.</p


__END__

=pod

=head1 NAME

Mojolicious::Plugin::Salmon - A Salmon Plugin for Mojolicious

=head1 SYNOPSIS

  use Mojolicious::Lite;

  plugin 'Salmon';

  my $r = app->routes;

  my $salmon = $r->route('/salmon');
  $salmon->route('/:user/mentioned')->salmon('mentioned');
  $salmon->route('/:user/all-replies')->salmon('all-replies');
  $salmon->route('/signer')->salmon('signer');

  app->start;

=head1 DESCRIPTION

L<Mojolicious::Plugin::Salmon> is a plugin for L<Mojolicious>
to work with Salmon as described in L<http://salmon-protocol.googlecode.com/svn/trunk/draft-panzer-salmon-00.html|Specification>.

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

=head1 AVAILABILITY

  https://github.com/Akron/Sojolicious

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2011, Nils Diewald.

This program is free software, you can redistribute it
and/or modify it under the same terms as Perl.

=cut
