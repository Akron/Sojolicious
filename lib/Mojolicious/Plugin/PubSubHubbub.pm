package Mojolicious::Plugin::PubSubHubbub;
use Mojo::Base 'Mojolicious::Plugin';
use Mojo::ByteStream ('b');
use Mojo::Util qw/trim/;

has [qw/hub host/];
has 'secure' => 0;

# Default lease seconds before automatic subscription refreshing
has lease_seconds => (30 * 24 * 60 * 60);


our ($global_param,
     @challenge_chars);

BEGIN {
    $global_param = {
	'Content-Type' =>
	    'application/x-www-form-urlencoded'
    };
    @challenge_chars = ('A' .. 'Z', 'a' .. 'z', 0 .. 9);
};

# Register plugin
sub register {
    my ($plugin, $mojo, $param) = @_;

    # Get host parameter
    if (exists $param->{host}) {
	$plugin->host( $param->{host} );
    } else {
	unless (exists $mojo->renderer->helpers->{'hostmeta'}) {
	    $plugin->host( $mojo->hostmeta('host') || 'localhost' );
	} else {
	    $plugin->host( 'localhost' );
	};
    };

    # Set secure
    $plugin->secure( $param->{secure} );

    # Add 'pubsub' shortcut
    $mojo->routes->add_shortcut(
	'pubsub' => sub {
	    my ($route, $param) = @_;

	    return unless $param eq 'cb'; # or $param eq 'hub';
	    # or $param eq 'hub'
	    # Internal hub is currently not supported
	    
	    # Set endpoint if enabled
	    if (exists $mojo->renderer->helpers->{'endpoint'}) {
		$route->endpoint(
		    'pubsub-'.$param => {
			scheme => $plugin->secure ? 'https' : 'http',
			host   => $plugin->host });
	    };

	    # Add 'callback' route
	    if ($param eq 'cb') {
		$route->to(
		    cb => sub {
			my $c = shift;

			# Hook on verification
			if ($c->param('hub.mode')) {
			    $plugin->verify( $c );
			}
			
			# Hook on callback
			else {
			    my $ct = $c->req->headers->header('Content-Type');

			    # Is Atom or RSS feed
			    if ($ct =~ m{application\/(?:rss|atom)\+xml}) {
				$plugin->callback($c);
			    }

			    # Bad request
			    else {
				return $c->render(
				    'template'       => 'pubsub-endpoint',
				    'template_class' => __PACKAGE__,
				    'status'         => 400 # bad request
				    );
			    };
			};
		    });
#	    }
#
# Add 'hub' route
# Not implemented yet
#	    else {
#		$route->via('post')
#		    ->to( cb => \&hub($plugin, @_) );
	    };

	});
    
    # Add 'publish' helper
    # $c->pubsub_publish('feed1', 'feed2', ...);
    $mojo->helper( 'pubsub_publish' => \&publish ); # ($plugin, @_) );
    
    # Add 'subscribe' helper
    $mojo->helper(
	'pubsub_subscribe' => sub {
	    return $plugin->change_subscription( shift,
						 mode => 'subscribe',
						 @_);
	});
    
    # Add 'unsubscribe' helper
    $mojo->helper(
	'pubsub_unsubscribe' => sub {
	    return $plugin->change_subscription( shift,
						 mode => 'unsubscribe',
						 @_ );
	});
};

# Ping a hub for topics
sub publish {
    my $plugin = shift;
    my $c      = shift;

    return unless @_;

    # Create post message
    my $post = 'hub.mode=publish';
    foreach ( @_ ) {
	next if $_ !~ m{^https?://}i;
	$post .= '&hub.url='.b($c->url_for($_)
			         ->to_abs
                                 ->to_string)->url_escape;
    };

    # Temporary
    return $post;

    # Post to hub
    # Todo: Maybe better post_form
    my $res = $c->ua
	->max_redirects(3)
	->post( $plugin->hub,
		$global_param,
		$post);

    # is 2xx, incl. 204 aka successful
    return 1 if $res->is_status_class(200);
    
    # Not successful
    return 0;
};

# Verify a changed subscription or automatically refresh
sub verify {
    my $plugin = shift;
    my $c = shift;

    # Not correct
    unless ($c->param('hub.mode') ||
	    $c->param('hub.topic') ||
	    $c->param('hub.challenge')) {

	return $c->render(
	    'template'       => 'pubsub-endpoint',
	    'template_class' => __PACKAGE__,
	    'status'         => 400  # bad request
	    );
    }
    
    # Correct
    else {
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

	# Run hook to see, if verification is granted.
	$plugin->app->run_hook( 'on_pubsub_verification' => (
				    $plugin,
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
sub change_subscription {
    my $plugin = shift;
    my $c      = shift;
    my %param  = @_;

    # No topic url given
    if (!exists $param{topic} || $param{topic} !~ m{^https?://}i ||
	!exists $param{hub}   || $param{hub}   !~ m{^https?://}i ) {
	return;
    };

    # delete lease seconds if no integer or not necessary
    if ( ( exists $param{lease_seconds} &&
	   $param{lease_seconds} =~ /^\d+$/
	 ) || $param{mode} eq 'unsubscribe') {
	delete $param{lease_seconds};
    };

    # Get callback endpoint
    # Works only if endpoints provided
    $param{'callback'} = $c->get_endpoint('pubsub-cb');

    # Render post string
    my $post = '';
    foreach ( qw/callback
                 mode
                 topic
                 verify
                 lease_seconds
                 secret/ ) {
	if (exists $param{$_}) {
	    $post .= '&hub.' . $_ . '='. b($param{$_})->url_escape;
	};
    };

    $post .= '&hub.verify_token=';
    if (exists $param{verify_token}) {
	$post .= b($param{verify_token})->url_escape;
    } else {
	$post .= ($param{verify_token} = _challenge(12));
    };

    $post .= '&hub.verify=' . $_ . 'sync' foreach ('a','');

    $plugin->app->run_hook(
	'before_pubsub_'.$param{mode} => ( $plugin
					   $c,
					   \%param,
					   \$post ));


    # Todo: better post_form
    # Temporary
    return $post;

    # Send subscription change to hub
    my $res = $c->ua
	->max_redirects(3)
	# wrong! hub!
	->post($param{hub},
	       $global_param,
	       $post);
    
    # is 2xx, incl. 204 aka successful
    #         and 202 aka accepted
    if ($res->is_status_class(200)) {
	return 1;
    } else {
	# Not successful
	return 0;
    };

# Todo with successvalue:
#    $plugin->app->run_hook(
#	'after_pubsub_'.$param{mode} => ( $plugin
#					  $c,
#					  \%param,
#					  $res->status,
#					  $res->body ));

};

sub callback {
    my $plugin = shift;
    my $c      = shift;

# Todo Verification:
# 1. Check if the feed is wanted
#    Atom: Maybe it is aggregated (bulk distribution).
#          In this case, all entry->sources have to be checked and
#          new feeds have to be generated.
# Proposal:
#  my $topics = ['https://wanted1', 'https://not-wanted', 'https://wanted2'];
#  my $secret = '';
#  $c->app->run_hook( 'on_pubsub_acceptance' => ($plugin, $c, $topics, \$secret ));
#  $topics eq ['https://wanted1', 'https://wanted2'];
#  $secret eq 'ngtdcbhjhbfgh';
# 2. If a secret was given, is there a signature?
#    my $req = $c->req;
#    my $signature = $req->headers->header('X-Hub-Signature');
#    $signature = s/^sha1=/;
#    $stream = b($req->body)->hmac_sha1_sum($secret);
# 3. If everything is allright:
#      foreach (entry that's wanted) {
#        Better 'on_pubsub_content'

    $c->app->run_hook( 'on_pubsub_callback' =>
		     ( $plugin, $c, $c->req ));
    
#      }
#    else ignore:
#    $c->log->info("Hub ($hub) sent ill-signed Feed ($feed)");

    # Possibly X-Hub-On-Behalf-Of header ...
    return $c->render(
	'status' => 204,
	'format' => 'text',
	'data'   => ''
	);
};

sub _challenge {
    my $chal;
    for (1..$_[0] || 8) {
        $chal .= $challenge_chars[int(rand(@challenge_chars))];
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
    <p>
      Your request was bad.
    </p>


__END__

=pod

=head1 NAME

Mojolicious::Plugin::PubSubHubbub

=head1 SYNOPSIS

  # Mojolicious
  $app->plugin('PubSubHubbub',
              { hub => 'https://hub.example.org/' }
              );

  my $r = $app->routes;
  $r->route('/:user/callback_url')->pubsub('cb')

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

  # Mojolicious::Lite
  plugin 'PubSubHubbub' => { hub => 'https://hub.example.org' };

  my $ps = any '/:user/callback_url';
  $ps->pubsub('cb);


=head1 DESCRIPTION

L<Mojolicious::Plugin::PubSubHubbub> is a plugin to support 
PubSubHubbub Webhooks
(see L<Specification|http://pubsubhubbub.googlecode.com/svn/trunk/pubsubhubbub-core-0.3.html>).

The plugin supports all three parties: publisher, subscriber, and hub.
However, be aware that the hub is implemented rather naive and does not scale well.
Please consider using a foreign hub or use a separated implementation for
the task by applying the L<on_hub_publish> hook.
The hub is not meant to be used as a generic hub - it should only serve local payloads
and allow for subscription and unsupscription to local feeds.
Additionally, the hub does no polling.

The plugin is data store agnostic. Please use this plugin by applying hooks.

=head1 ATTRIBUTES

=head2 C<host>

  $ps->host('sojolicio.us');
  my $host = $ps->host;

The host for the PubSubHubbub enabled domain.

=head2 C<secure>

  $ps->secure(1);
  my $sec = $wf->secure;

Use C<http> or C<https>.

=head2 C<hub>

  $ps->hub('http://pubsubhubbub.appspot.com/');
  my $hub = $ps->hub;

The preferred hub. Currently local hubs are not implemented.

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

Publish a list of feeds.

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

=head2 C<unsubscribe>

  # In Controllers
  $c->unsubscribe(topic => 'https://sojolicio.us/feed.atom',
                  hub   => 'https://hub.sojolicio.us' );

Unsubscribe from a topic.
Relevant parameters are 'hub', 'secret', and 'verify_token'.
Additional parameters are possible and can be used in the hooks.

=head1 HOOKS

=head2 C<on_pubsub_callback>

This hook is released, when desired content is send to the pubsub
endpoint. The parameters include the plugin object, the current
Controller object and the request object.

This hook is EXPERIMENTAL. In next versions, this hook may not contain
the request object but a feed object, that can differ from what the hub
has sent (In case of, e.g., bulk distribution).

=head2 C<before_pubsub_subscribe>

This hook is released, before a subscription request is sent to a hub.
The parameters include the Plugin, the current Controllers object, the
parameters for subscription as a Hash ref and the C<POST> string as a
string ref.
This hook can be used to store subscription information and establish
a secret value.

=head2 C<before_pubsub_unsubscribe>

This hook is released, before an unsubscription request is sent
to a hub.
The parameters include the Plugin, the current Controllers object, the
parameters for subscription as a Hash ref and the C<POST> string as a
string ref.
This hook can be used to store unsubscription information.

=head2 C<on_pubsub_verification>

This hook is released, when a verification is requested. The parameters
are the Plugin, the current controller object, and a string reference to a
false value. If verification is granted, this value has to be set to true.

=head1 DEPENDENCIES

L<Mojolicious>,
L<Mojolicious::Plugin::Util::Endpoint> (optional).

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2011, Nils Diewald.

This program is free software, you can redistribute it
and/or modify it under the same terms as Perl.

=cut
