package Mojolicious::Plugin::PubSubHubbub;
use Mojo::Base 'Mojolicious::Plugin';
use Mojo::ByteStream 'b';
use Mojo::Util qw/trim/;
use Mojo::IOLoop;

use constant ATOM_NS => 'http://www.w3.org/2005/Atom';

has 'host';
has 'secure' => 0;

# Default lease seconds before automatic subscription refreshing
has 'lease_seconds' => (30 * 24 * 60 * 60);
has 'hub';

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
	if (exists $mojo->renderer->helpers->{'hostmeta'}) {
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

	    return unless $param eq 'cb';
	    # 'hub' is currently not supported
	    
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
			    $plugin->callback($c);
			};
		    });
	    };

	});
    
    # Add 'publish' helper
    $mojo->helper( 'pubsub_publish' => \&publish );
    
    # Add 'subscribe' helper
    $mojo->helper(
	'pubsub_subscribe' => sub {
	    return $plugin->_change_subscription( shift,
						  mode => 'subscribe',
						  @_);
	});
    
    # Add 'unsubscribe' helper
    $mojo->helper(
	'pubsub_unsubscribe' => sub {
	    return $plugin->_change_subscription( shift,
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
	$post .= '&hub.url='.b($c->url_for($_)
			         ->to_abs
                                 ->to_string)->url_escape;
    };

    # Temporary
    # return $post;

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
sub _change_subscription {
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
	'before_pubsub_'.$param{mode} => ( $plugin,
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

    $plugin->app->run_hook(
	'after_pubsub_'.$param{mode} => ( $plugin,
					  $c,
					  \%param,
					  $res->status,
					  $res->body ));

    my $success = $res->is_status_class(200) ? 1 : 0;

    return ($success, $res->{body}) if wantarray;
    return $success;
};

# Incoming data callback
sub callback {
    my $plugin = shift;
    my $c      = shift;
    my $mojo   = $c->app;

    # Find topics in Payload
    my ($type,
	$topics,
	$dom,
	$aggregated) = _find_topics($c);

    # Payload had wrong content type
    return $c->render(
	'template'       => 'pubsub-endpoint',
	'template_class' => __PACKAGE__,
	'status'         => 400 # bad request
	) unless $type;

    # No topics to process
    return _render_success($c) unless $topics->[0];
    
    my $secret;
    my $x_hub_on_behalf_of = 0;

    my @old_topics = @$topics;

    # Check for secret and which topics are wanted
    $mojo->run_hook(
	'on_pubsub_acceptance' => ( $plugin,
				    $c,
				    $topics,
				    \$secret,
				    \$x_hub_on_behalf_of ));
    
    _render_success( $c => $x_hub_on_behalf_of );

    # No topics to process
    return unless $topics->[0];

    # Process content
    Mojo::IOLoop->timer(
	0 => sub {
	    
	    # Secret is needed
	    if ($secret) {
		return unless _check_signature($c, $secret);
	    };
	    
	    # Some topics are unwanted
	    if (@$topics != @old_topics) {
		# filter dom based on topics
		$dom = _filter_topics($dom, $type, $topics);
	    };
	    
	    $mojo->run_hook( 'on_pubsub_content' =>
			     ( $plugin,
			       $c,
			       $type,
			       $dom ));
	    return;
	});

    return;
};

# Find topics of entries
sub _find_topics {
    my $c = shift;

    # No secret
    my ($dom,
	@topics,
	$type);

    my $aggregated = 0;

    my $ct = $c->req->headers->header('Content-Type') || 'text';

    # Is RSS
    if ($ct eq 'application/rss+xml') {
	$type = 'rss';

	$dom = $c->req->dom;

	# From Atom namespace
	my $link = $dom->at('channel > link[rel="self"]');
	@topics = $link->attrs('href') if $link;

	unless (@topics) {
	    # Possible
	    $link = $dom->at('channel > item > source');
	    @topics = $link->attrs('url') if $link;
	};
    }

    # Is Atom
    elsif ($ct eq 'application/atom+xml') {
	$type = 'atom';

	$dom = $c->req->dom;

	# Possibly aggregated feed
	$aggregated = 1;

	my $link = $dom->find('feed > entry > source > link[rel="self"]');
	@topics = $link->map( sub { $_->attrs('href') } ) if $link;

	# obviously not aggregated
	if (!@topics) {

	    # One feed or entry
	    $link = $dom->at('link[rel="self"]');

	    @topics = $link->attrs('href') if $link;

	    # Not aggregated
	    $aggregated = 0;
	}

        # Make unique
	elsif (@topics > 1) {

	    my %topics = map {$_ => 1 } @topics;
	    @topics = keys %topics;
	}

	# Not aggregated
	else {
	    $aggregated = 0;
	};
    }

    # Unsupported content type
    else {
	return;
    };

    return ($type, \@topics, $dom, $aggregated)
};

# filter entries based on their topic 
sub _filter_topics {
    my $dom     = shift;
    my $type    = shift;
    my %allowed = map { $_ => 1 } @{ shift(@_) };

    my $topic_elem = $dom->at('link[rel="self"]');
    my $feed_topic = $topic_elem->attrs('href') if $topic_elem;

    # atom entries
    if ($type eq 'atom') {
	$dom->find('entry')->each(
	    sub {
		my $entry = shift;
		
		# Find topic of the entry
		$topic_elem =
		    $entry->at('source > link[rel="self"]');
		my $topic = $topic_elem ?
		    $topic_elem->attrs('href') : $feed_topic;
		
		# Delete entry
		unless ($topic || exists $allowed{$topic}) {
		    $entry->replace('');
		};
		return;
	    });
    }

    # rss entries
    else {
	$dom->find('item')->each(
	    sub {
		my $entry = shift;
		
		# Find topic of the entry
		my $topic;
		$topic_elem = $entry->at('source[url]');
		
		if ($topic_elem) {
		    $topic = $topic_elem->attrs('url');
		} else {
		    $topic_elem =
			$entry->at('source > link[rel="self"]');
		    $topic = $topic_elem ?
			$topic_elem->attrs('href') : $feed_topic;
		};
		
		# Delete entry
		unless ($topic || exists $allowed{$topic}) {
		    $entry->replace('');
		};
		return;
	    });
    };
    return $dom;
};

# Check signature
sub _check_signature {
    my ($c, $secret) = @_;

    my $req = $c->req;
	    
    # Get signature
    my $signature = $req->headers->header('X-Hub-Signature');
	    
    # Signature expected but not given
    return unless $signature;
	    
    $signature = s/^sha1=//;
	    
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

  (any '/:user/callback_url')->pubsub('cb');


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

=head2 C<before_pubsub_acceptance>

This hook is released, when content arrived the pubsub
endpoint. The parameters include the plugin object, the current
Controller object an array reference of topics, an empty string
reference for a possible secret, and a string reference
for the C<X-Hub-On-Behalf-Of> value, initially 0.

This hook can be used to filter unwanted topics, to give a
necessary secret for signed content, and information on
the user count of the subscription to the processor.

If the list is returned as an empty list, the processing will stop.

If nothing in this hook happens, the complete content will be processed.

=head2 C<on_pubsub_content>

This hook is released, when desired content is delivered.
The parameters include the plugin object, the current
Controller object, and chunks of th content as a
L<Mojo::DOM> object.
If a feed containing multiple entries is returned (whether
as an aggregated bulk feed with multiple topics or a simple
feed with multiple entries on one topic) each entry will
invoke this hook.

=head2 C<before_pubsub_subscribe>

This hook is released, before a subscription request is sent to a hub.
The parameters include the Plugin, the current Controllers object, the
parameters for subscription as a Hash ref and the C<POST> string as a
string ref.
This hook can be used to store subscription information and establish
a secret value.

=head2 C<after_pubsub_subscribe>

This hook is released, after a subscription request is sent to a hub
and the response is processed.
The parameters include the Plugin, the current Controllers object, the
parameters for subscription as a Hash ref, the response status, and
the response body.
This hook can be used to deal with errors.

=head2 C<before_pubsub_unsubscribe>

This hook is released, before an unsubscription request is sent
to a hub.
The parameters include the Plugin, the current Controllers object, the
parameters for subscription as a Hash ref and the C<POST> string as a
string ref.
This hook can be used to store unsubscription information.

=head2 C<after_pubsub_unsubscribe>

This hook is released, after an unsubscription request is sent to a hub
and the response is processed.
The parameters include the Plugin, the current Controllers object, the
parameters for subscription as a Hash ref, the response status, and
the response body.
This hook can be used to deal with errors.

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
