package Mojolicious::Plugin::PubSubHubbub;
use Mojo::Base 'Mojolicious::Plugin';
use Mojo::ByteStream 'b';
use Mojo::DOM;

use constant ATOM_NS => 'http://www.w3.org/2005/Atom';

# Default lease seconds before automatic subscription refreshing
has 'lease_seconds' => ( 30 * 24 * 60 * 60 );
has 'hub';

# Character set for challenge
my @challenge_chars = ('A' .. 'Z', 'a' .. 'z', 0 .. 9 );

# Register plugin
sub register {
  my ($plugin, $mojo, $param) = @_;

  $plugin->hub($param->{hub}) if $param->{hub};

  # Add 'pubsub' shortcut
  $mojo->routes->add_shortcut(
    'pubsub' => sub {
      my ($route, $param) = @_;

      # 'hub' is currently not supported
      return unless $param eq 'cb';

      # Load 'endpoint' plugin
      unless (exists $mojo->renderer->helpers->{'endpoint'}) {
	$mojo->plugin('Util::Endpoint');
      };

      # Set PubSubHubbub endpoints
      $route->endpoint('pubsub-' . $param);

      # Add 'callback' route
      if ($param eq 'cb') {
	$route->to(
	  cb => sub {
	    my $c = shift;

	    # Hook on verification
	    return $plugin->verify($c) if $c->param('hub.mode');

	    # Hook on callback
	    return $plugin->callback($c);
	  });
      };
    });

  # Add 'publish' helper
  $mojo->helper(
    'pubsub_publish' => sub {
      $plugin->publish( @_ );
    });

  # Add 'subscribe' and 'unsubscribe' helper
  foreach my $action (qw(subscribe unsubscribe)) {
    $mojo->helper(
      'pubsub_' . $action => sub {
	return $plugin->_change_subscription( shift,
					      mode => $action,
					      @_);
      });
  };
};


# Ping a hub for topics
sub publish {
  my $plugin = shift;
  my $c      = shift;

  # Nothing to publish or no hub defined
  return unless @_ || !$plugin->hub;

  # Set all urls
  my @urls = map($c->endpoint($_), @_);

  # Create post message
  my %post = ( 'hub.mode' => 'publish',
	       'hub.url' => \@urls);

  # Post to hub
  my $res = $c->ua
    ->max_redirects(3)
      ->post_form( $plugin->hub, \%post )->res;

  # No response
  unless ($res) {
    $c->app->log->debug('Cannot ping hub - maybe no SSL support')
      if index($plugin->hub, 'https') == 0;
    return;
  };

  # is 2xx, incl. 204 aka successful
  return 1 if $res->is_status_class(200);

  # Not successful
  return;
};


# Verify a changed subscription or automatically refresh
sub verify {
  my $plugin = shift;
  my $c = shift;

  # Good request
  if ($c->param('hub.topic') &&
      $c->param('hub.challenge') &&
      $c->param('hub.mode') =~ /^(?:un)?subscribe$/) {

    my $challenge = $c->param('hub.challenge');

    # Not verified
    my $ok = 0;

    my %param;
    foreach (qw/mode
		topic
		verify
		lease_seconds
		verify_token/) {
      $param{$_} = $c->param('hub.'.$_) if $c->param('hub.'.$_);
    };

    # Emit hook to see, if verification is granted.
    $c->app->plugins->emit_hook( 'on_pubsub_verification' =>
				  ( $plugin,
				    $c,
				    \%param,
				    \$ok ) );

    if ($ok) {
      return $c->render(
	'status' => 200,
	'format' => 'text',
	'data'   => $challenge
      );
    };
  };

  # Not found
  return $c->render_not_found;
};


# subscribe or unsubscribe from a topic
sub _change_subscription {
  my $plugin = shift;
  my $c      = shift;
  my %param  = @_;

  # Get callback endpoint
  # Works only if endpoints provided
  unless ($param{callback} = $c->endpoint('pubsub-cb')) {
    $c->app->log->warn('You have to specify a callback endpoint.');
  };

  # No topic or hub url given
  if (!exists $param{topic} || $param{topic} !~ m{^https?://}i ||
      !exists $param{hub}) {
    return;
  };

  my $mode = $param{mode};

  # delete lease seconds if no integer
  if ( exists $param{lease_seconds} &&
	 ($mode eq 'unsubscribe' ||
	    $param{lease_seconds} !~ /^\d+$/) ) {
    delete $param{lease_seconds};
  }

  # Set to default
  $param{lease_seconds} ||= $plugin->lease_seconds
    if $mode eq 'subscribe';

  # Render post string
  my %post = ( callback => $param{callback} );
  foreach ( qw/mode topic verify lease_seconds secret/ ) {
    $post{ $_ } = $param{ $_ } if exists $param{ $_ } && $param{ $_ };
  };

  # Use verify token
  $post{'verify_token'} = exists $param{verify_token} ?
                          $param{verify_token} :
			  ($param{verify_token} = _challenge(12));

  $post{'verify'} = $_ . 'sync' foreach ('a','');

  my $mojo = $c->app;

  $mojo->plugins->emit_hook(
    'before_pubsub_'.$mode => ( $plugin,
				$c,
				\%param,
				\%post ));

  # Prefix all parameters
  %post = map {'hub.' . $_ => $post{$_} } keys %post;

  # Send subscription change to hub
  my $res = $c->ua
    ->max_redirects(3)
    ->post_form($param{hub}, \%post)->res;

  # No response
  unless ($res) {
    $mojo->log->debug('Cannot ping hub - maybe no SSL support installed?')
      if index($plugin->hub, 'https') == 0;
    return;
  };

  $mojo->plugins->emit_hook(
    'after_pubsub_'.$mode => ( $plugin,
			       $c,
			       \%param,
			       $res->code,
			       $res->body ));

  # is 2xx, incl. 204 aka successful and 202 aka accepted
  my $success = $res->is_status_class(200) ? 1 : 0;

  return ($success, $res->{body}) if wantarray;
  return $success;
};


# Incoming data callback
sub callback {
  my $plugin = shift;
  my $c      = shift;
  my $mojo   = $c->app;

  my $ct = $c->req->headers->header('Content-Type') || 'unknown';
  my $type;

  # Is Atom
  if ($ct eq 'application/atom+xml') {
    $type = 'atom';
  }

  # Is RSS
  elsif ($ct =~ m{^application/r(?:ss|df)\+xml$}) {
    $type = 'rss';
  }

  # Unsupported content type
  else {
    $mojo->log->debug('Unsupported media type: ' . $ct);
    return _render_fail($c);
  };

  my $dom = Mojo::DOM->new;
  $dom->xml(1)->parse($c->req->body);

  # Find topics in Payload
  my $topics = _find_topics($type, $dom);

  # No topics to process - but technically fine
  return _render_success($c) unless $topics->[0];

  my $secret;
  my $x_hub_on_behalf_of = 0;

  # Save unfiltered topics for later comparison
  my @old_topics = @$topics;

  # Check for secret and which topics are wanted
  $mojo->plugins->emit_hook(
    'on_pubsub_acceptance' => ( $plugin,
				$c,
				$type,
				$topics,
				\$secret,
				\$x_hub_on_behalf_of ));

  # No topics to process
  return _render_success( $c => $x_hub_on_behalf_of )
    unless $topics->[0];

# Asynchronous is hard
#  todo: $c->on(finish =>

  # Secret is needed
  if ($secret) {

    # Unable to verify secret
    unless ( _check_signature( $c, $secret )) {
      $mojo->log->debug('Unable to verify secret for ' . join('; ',@$topics));
      return _render_success( $c => $x_hub_on_behalf_of );
    };
  };

  # Some topics are unwanted
  if (@$topics != @old_topics) {

    # filter dom based on topics
    $topics = _filter_topics($dom, $topics);
  };

  $mojo->plugins->emit_hook( 'on_pubsub_content' =>
			       ( $plugin,
				 $c,
				 $type,
				 $dom ));
#    });

  return _render_success( $c => $x_hub_on_behalf_of );
};


# Find topics of entries
sub _find_topics {
  my $type = shift;
  my $dom  = shift;

  # Get all source links
  my $links = $dom->find('source > link[rel="self"][href]');

  # Save href as topics
  my @topics = @{ $links->map( sub { $_->attrs('href') } ) } if $links;

  # Find all entries, regardless if rss or atom
  my $entries = $dom->find('item, feed > entry');

  # Not every entry has a source
  if ($links->size != $entries->size) {

    # One feed or entry
    my $link = $dom->at('feed > link[rel="self"][href],'.
			'channel > link[rel="self"][href]');

    my $self_href;

    # Channel or feed link
    if ( $link ) {
      $self_href = $link->attrs('href');
    }

    # Source of first item in RSS
    elsif ( !$self_href && $type eq 'rss' ) {

      # Possible
      $link = $dom->at('item > source');
      $self_href = $link->attrs('url') if $link;
    };

    # Add topic to all entries
    _add_topics($type, $dom, $self_href) if $self_href;

    # Get all source links
    $links = $dom->find('source > link[rel="self"][href]');

    # Save href as topics
    @topics = @{ $links->map( sub { $_->attrs('href') } ) } if $links;
  };

  if (@topics > 1) {
    my %topics = map { $_ => 1 } @topics;
    @topics = keys %topics;
  };

  return \@topics;
};


# Add topic to entries
sub _add_topics {
  my ($type, $dom, $self_href) = @_;

  my $link = '<link rel="self" href="' . $self_href . '" />';

  # Add source information to each entry
  $dom->find('item, entry')->each(
    sub {
      my $entry = shift;
      my $source;

      # Sources are found
      if (my $sources = $entry->find('source')) {
	foreach my $s (@$sources) {
	  if ($s->namespace eq ATOM_NS) {
	    $source = $s;
	    last;
	  };
	};
      };

      # No source found
      unless ($source) {
	$source = $entry->append_content('<source xmlns="' . ATOM_NS . '" />')
	  ->at('source[xmlns=' . ATOM_NS . ']');
      }

      # Link already there
      elsif ($source->at('link[rel="self"][href]')) {
	return $dom;
      };

      # Add link
      $source->append_content( $link );
    });

  return $dom;
};


# filter entries based on their topic
sub _filter_topics {
  my $dom     = shift;

  my %allowed = map { $_ => 1 } @{ shift(@_) };

  my $links = $dom->find('feed > entry > source > link[rel="self"][href],' .
	                 'item  > source > link[rel="self"][href]');

  my %topics;

  # Delete entries that are not allowed
  $links->each(
    sub {
      my $l = shift;
      my $href = $l->attrs('href');

      unless (exists $allowed{$href}) {
	$l->parent->parent->replace('');
      }

      else {
	$topics{$href} = 1;
      };
    });

  return [ keys %topics ];
};


# Check signature
sub _check_signature {
  my ($c, $secret) = @_;

  my $req = $c->req;

  # Get signature
  my $signature = $req->headers->header('X-Hub-Signature');

  # Signature expected but not given
  return unless $signature;

  # Delete signature prefix - don't remind, if it's not there.
  $signature =~ s/^sha1=//i;

  # Generate check signature
  my $signature_check = b($req->body)->hmac_sha1_sum( $secret );

  # Return true  if signature check succeeds
  return 1 if $signature eq $signature_check;

  return;
};


# Render success
sub _render_success {
  my $c = shift;
  my $x_hub_on_behalf_of = shift;

  # Set X-Hub-On-Behalf-Of header
  if ($x_hub_on_behalf_of &&
	$x_hub_on_behalf_of =~ /^\d+$/) {
    $c->res->headers->header('X-Hub-On-Behalf-Of' =>
			       $x_hub_on_behalf_of);
  };

  # Render success with no content
  return $c->render(
    'status' => 204,
    'format' => 'text',
    'data'   => ''
  );
};

# Render fail
sub _render_fail {
  return shift->render(
    'template'       => 'pubsub-endpoint',
    'template_class' => __PACKAGE__,
    'status'         => 400  # bad request
  );
};


# Create challenge string
sub _challenge {
  my $chal = '';
  for (1..$_[0] || 8) {
    $chal .= $challenge_chars[ int( rand( @challenge_chars ) ) ];
  };
  return $chal;
};

1;

__DATA__
@@ layouts/pubsub.html.ep
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

@@ pubsub-endpoint.html.ep
% layout 'pubsub', title => 'PubSubHubbub Endpoint';
    <p>
      This is an endpoint for the
      <a href="http://pubsubhubbub.googlecode.com/svn/trunk/pubsubhubbub-core-0.3.html">PubSubHubbub protocol</a>
    </p>
    <p>Your request was not correct.</p>


__END__

=pod

=head1 NAME

Mojolicious::Plugin::PubSubHubbub - PubSubHubbub Plugin for Mojolicious

=head1 SYNOPSIS

  # Mojolicious
  $app->plugin('PubSubHubbub',
              { hub => 'https://hub.example.org/' }
              );

  my $r = $app->routes;
  $r->route('/:user/callback_url')->pubsub('cb')

  # Mojolicious::Lite
  plugin 'PubSubHubbub' => { hub => 'https://hub.example.org' };

  (any '/:user/callback_url')->pubsub('cb');

  # In Controllers:
  # Publish a feed
  $c->publish('https://sojolicio.us/blog.atom',
              'https://sojolicio.us/activity.atom');

  # Subscribe to a feed
  $c->subscribe( topic   => 'https://sojolicio.us/feed.atom',
                 hub     => 'https://hub.sojolicio.us');

  # Unsubscribe from a feed
  $c->unsubscribe( topic => 'https://sojolicio.us/feed.atom',
                   hub   => 'https://hub.sojolicio.us' );

=head1 DESCRIPTION

L<Mojolicious::Plugin::PubSubHubbub> is a plugin to support
PubSubHubbub Webhooks as described in
L<http://pubsubhubbub.googlecode.com/svn/trunk/pubsubhubbub-core-0.3.html|Specification>.

The plugin currently supports the publisher and subscriber part,
not the hub part.

The plugin is data store agnostic. Please use this plugin by applying hooks.

=head1 ATTRIBUTES

=head2 C<hub>

  $ps->hub('http://pubsubhubbub.appspot.com/');
  my $hub = $ps->hub;

The preferred hub. Currently local hubs are not supported.

=head2 C<lease_seconds>

  my $seconds = $ps->lease_seconds;
  $ps->lease_seconds(100 * 24 * 60 * 60);

Seconds a subscription is valid by default before auto refresh
is enabled.

=head1 HELPERS

=head2 C<publish>

  # In Controllers
  $c->publish( 'my_feed',                       # named route
               '/feed.atom',                    # relative paths
               'https://sojolicio.us/feed.atom' # absolute uris
             ):

Publish a list of feeds in terms of a notification to the hub.

=head2 C<subscribe>

  # In Controllers
  $c->subscribe(topic => 'https://sojolicio.us/feed.atom',
                hub   => 'https://hub.sojolicio.us' );
                lease_seconds => 123456 );

Subscribe to a topic.

Relevant parameters are 'hub',
'lease_seconds', 'secret', 'verify_token', and 'callback'.
Additional parameters are possible and can be used in the hooks.
If no 'verify_token' is given, it is automatically generated.
If no 'callback' is given, the route callback is used.
If no 'lease_seconds' is given, the subscription will
not automatically terminate.
If a secret is given, it must be unique for every 'callback'
and 'hub' combination to allow fur bulk distribution.
The method returns a true value on succes and a false value
if an error occured. If called in an array context, the
hub's response message body is returned additionally.

=head2 C<unsubscribe>

  # In Controllers
  $c->unsubscribe(topic => 'https://sojolicio.us/feed.atom',
                  hub   => 'https://hub.sojolicio.us' );

Unsubscribe from a topic.

Relevant parameters are 'hub', 'secret', and 'verify_token'.
Additional parameters are possible and can be used in the hooks.
The method returns a true value on succes and a false value
if an error occured. If called in an array context, the
hub's response message body is returned additionally.

=head1 HOOKS

=head2 C<on_pubsub_acceptance>

  $mojo->hook(
    on_pubsub_acceptance' > sub {
      my ($plugin, $c, $type,
          $topics, $secret, $on_behalf) = @_;

      @$topics = grep($_ !~ /catz/, @$topics);
      $$secret = 'zoidberg';
      $$on_behalf = 3;

      return;
     });

This hook is released, when content arrived the pubsub
endpoint. The parameters include the plugin object, the current
controller object, the content type, an array reference of topics,
an empty string reference for a possible secret, and a string
reference for the C<X-Hub-On-Behalf-Of> value, initially 0.

This hook can be used to filter unwanted topics, to give a
necessary secret for signed content, and information on
the user count of the subscription to the processor.

If the list is returned as an empty list, the processing will stop.

If nothing in this hook happens, the complete content will be processed.

=head2 C<on_pubsub_content>

  $mojo->hook(
    on_pubsub_content => sub {
      my ($plugin, $c, $type, $dom) = @_;

      if ($type eq 'atom') {
        $dom->find('entry')->each(
          print $_->at('title')->text, "\n";
        );
      };

      return;
    });

This hook is released, when desired (i.e., verified and filtered)
content is delivered.
The parameters include the plugin object, the current
controller object, the content type, and the - maybe topic
filtered - content as a L<Mojo::DOM> object.

The L<Mojo::DOM> object is modified in a way that each entry in
the feed (either RSS or Atom) includes its topic in
'source link[rel="self"][href]'.

=head2 C<before_pubsub_subscribe>

  $mojo->hook(
    before_pubsub_subscribe => sub {
      my ($plugin, $c, $params, $post) = @_;

      my $topic = $params->{topic};
      print "Start following $topic\n";

      return;
    });

This hook is released, before a subscription request is sent to a hub.
The parameters include the plugin object, the current controller object,
the parameters for subscription as a Hash reference and the C<POST>
string as a string ref.
This hook can be used to store subscription information and establish
a secret value.

=head2 C<after_pubsub_subscribe>

  $mojo->hook(
    after_pubsub_subscribe => sub {
      my ($plugin, $c, $params, $status, $body) = @_;
      if ($status !~ /^2/) {
        warn 'Error: ', $body;
      };

      return;
    });

This hook is released, after a subscription request is sent to a hub
and the response is processed.
The parameters include the plugin object, the current controller object,
the parameters for subscription as a Hash reference, the response status,
and the response body.
This hook can be used to deal with errors.

=head2 C<before_pubsub_unsubscribe>

  $mojo->hook(
    before_pubsub_unsubscribe => sub {
      my ($plugin, $c, $params, $post) = @_;

      my $topic = $params->{topic};
      print "Stop following $topic\n";

      return;
    });

This hook is released, before an unsubscription request is sent
to a hub.
The parameters include the plugin object, the current controller object,
the parameters for unsubscription as a Hash reference and the C<POST>
string as a string ref.
This hook can be used to store unsubscription information.

=head2 C<after_pubsub_unsubscribe>

  $mojo->hook(
    after_pubsub_unsubscribe => sub {
      my ($plugin, $c, $params, $status, $body) = @_;
      if ($status !~ /^2/) {
        warn 'Error: ', $body;
      };

      return;
    });

This hook is released, after an unsubscription request is sent to a hub
and the response is processed.
The parameters include the plugin object, the current controller object,
the parameters for unsubscription as a Hash reference, the response status,
and the response body.
This hook can be used to deal with errors.

=head2 C<on_pubsub_verification>

  $mojo->hook(
    on_pubsub_verification => sub {
      my ($plugin, $c, $params, $ok_ref) = @_;

      if ($params->{topic} =~ /catz/ &&
          $params->{verify_token} eq 'zoidberg') {
        $$ok_ref = 1;
      };

      return;
    });

This hook is released, when a verification is requested. The parameters
are the plugin object, the current controller object, the parameters
of the verification request as a Hash reference, and a string reference
to a false value.
If verification is granted, this value has to be set to true.

=head1 DEPENDENCIES

L<Mojolicious>,
L<Mojolicious::Plugin::Util::Endpoint>.

=head1 AVAILABILITY

  https://github.com/Akron/Sojolicious

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2011, Nils Diewald.

This program is free software, you can redistribute it
and/or modify it under the same terms as Perl.

=cut
