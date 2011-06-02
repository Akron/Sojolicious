package Mojolicious::Plugin::Salmon;
use strict;
use warnings;
use Mojo::Base 'Mojolicious::Plugin';

has qw/host/;

# Register plugin
sub register {
    my ($plugin, $mojo, $param) = @_;

    my $helpers = $mojo->renderer->helpers;

    # Load magic signatures if not loaded
    unless (exists $helpers->{'magicenvelope'}) {
	$mojo->plugin('magic_signatures', {'host' => $param->{'host'}} );
    };

    # Load webfinger if not loaded
    unless (exists $helpers->{'webfinger'}) {
	$mojo->plugin('webfinger', {'host' => $param->{'host'}} );
    };

    # Load host meta if not loaded
    unless (exists $helpers->{'hostmeta'}) {
	$mojo->plugin('host_meta', {'host' => $param->{'host'}} );
    };

    # set host
    if (defined $param->{host}) {
	$plugin->host($param->{host});
    } else {
	$plugin->host( $mojo->hostmeta('host') || 'localhost' );
    };

    # Does it need ssl or not
    $plugin->secure( $param->{host} );

    $mojo->routes->add_shortcut(
	'salmon' => sub {
	    my $route = shift;
	    my $param = shift;

	    warn 'Unknown Salmon parameter' && return
		if $param !~ /^(mentioned|all-replies|signer)$/;


	    # Handle GET requests
	    $route->get->to(
		'cb' => sub {
		    return shift->render(
			'template'       => 'salmon-endpoint',
			'template_class' => __PACKAGE__,
			'status'         => 400 # bad request
			);
		});

	    # Set the route name
 	    my $r_name = 'salmon-'.$param;
	    if ($plugin->app->url_for{$r_name}) {
		warn qq{Route $r_name already defined.};
		return;
	    };
	    $route->name($r_name);

	    if ($param eq 'all-replies') {

		# Handle POST requests
		$route->post->to(
		    'cb' => sub {
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

			    my $author = $self->discover_author($me);
			};

#			$plugin->salmon(@_)

# Hook 'after-salmon-reply'

			# Ceck Timestamp
			# 400 if not valid

			# Further Checks. Via hook.
			
 			$c->app->plugins->run_hook('on_salmon_reply' => $c, $me);

			unless ($c->rendered) {
			    $c->render(
				status => 200,
				template => 'salmon-reply'
				);
			};

			return;
		    }
		    );
	    }

	    # Mention route
	    elsif ($param eq 'mentioned') {
		# Handle POST requests
		$route->post->to(
		    'cb' => sub {
# Hook 'before-salmon-mention'

# Hook 'on-salmon-mention'

			$plugin->salmon(@_)
		    }
		    );
		
	    }

	    # Signer route
	    elsif ($param eq 'signer') {

		# Todo: Fragen: Gibt es schon eine Signer-URI?

# Hook 'before-salmon-sign'

		my $salmon_signer_url = 
		    $plugin->secure.
		    $plugin->host.
		    $mojo->url_for('salmon-signer')->to_abs;

		# Add signer link to host-meta
		my $link = $mojo->hostmeta->add(
		    'Link', {
			rel => 'salmon-signer',
			href => $salmon_signer_url
		    });
		$link->comment('Salmon Signer');
		$link->add('Title', 'Salmon Endpoint');

# Hook 'after-salmon-sign'

		$route->post->to(
		    'cb' => sub {
			$plugin->salmon_signer( @_ );
		    }
		    );
	    }

	    else {
		warn 'wrong';
	    };  
	}
	);
};

sub secure {
    my $self = shift;

    unless (defined $_[0]) {
	if (defined $self->{secure}) {
	    return 'https://';
	} else {
	    return 'http://';
	};
    } elsif ($_[0]) {
	$self->{secure} = 1;
    } else {
	$self->{secure} = undef;
    };
};


sub salmon {
    my $plugin = shift;
    my $c = shift;

    my $content_type = $c->req->headers->content_type;

    my $me_app = 'application/magic-envelope';

    if ($content_type eq $me_app.'+xml') {

	my ($unwrapped_content_type,
	    $unwrapped_body) =
	    $c->me_unwrap($c->req->body);

	$c->render_text(
	    $unwrapped_content_type."\n\n".
	    $unwrapped_body
	    );

    }

    elsif ($content_type eq $me_app.'+json') {

    }

    else {
	$c->render_text('Booh! No me!');
    };    
};

# to be implemented!
sub salmon_signer {
    my $plugin = shift;

    warn 'Salmon signer is not yet implemented.';

    my $c = shift;

    # Check OAuth token
    # 401 if not correct
    # ...

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

sub discover_author {
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
   <p>Thank you for your reply</p

__END__

