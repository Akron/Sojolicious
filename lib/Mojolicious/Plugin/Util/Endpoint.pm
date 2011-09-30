package Mojolicious::Plugin::Util::Endpoint;
use Mojo::Base 'Mojolicious::Plugin';
use Mojo::ByteStream 'b';
use Mojo::URL;

# Endpoint hash
our %endpoints;

# Register Plugin
sub register {
  my ($plugin, $mojo, $param) = @_;

  # Add 'endpoint' shortcut
  $mojo->routes->add_shortcut(
    'endpoint' => sub {
      my ($route, $name, $param) = @_;

      # Endpoint already defined
      if (exists $endpoints{$name}) {
	$mojo->log->debug(qq{Route endpoint "$name" already defined.});
	return $route;
      };

      # Route defined
      $route->name($name);

      # Search for placeholders
      my %placeholders;
      my $r = $route;
      $r->pattern->match('/');
      while ($r) {
	foreach (@{$r->pattern->symbols}) {
	  $placeholders{$_} = '{' . $_ . '}';
	};
	$r = $r->parent;
      };

      # Set Endpoint url
      my $endpoint_url = $mojo->url_for($name => 
					  %placeholders)->to_abs->clone;

      for ($endpoint_url) {

	# Host
	$_->host($param->{host}) if exists $param->{host};

	# Port
	$_->port( $param->{port} ) if exists $param->{port};

	# Scheme
	if (exists $param->{scheme}) {
	  $_->scheme( $param->{scheme} );
	}

	# Secure flag
	# This is DEPRECATED!
	elsif (exists $param->{secure}) {
	  $mojo->log->warn('secure is deprecated!');
	  $_->scheme( $param->{secure} ? 'https' : 'http' );
	}

	# Defaults to http
	else {
	  $_->scheme( 'http' );
	};

	# Set query parameter
	if (exists $param->{query}) {
	  $_->query( $param->{query} );
	};
      };

      my $endpoint = $endpoint_url->to_string;

      # Unescape template variables
      $endpoint =~
	s/\%7[bB](.+?)%7[dD]/'{'.b($1)->url_unescape.'}'/ge;

      # Set to stash
      $endpoints{$name} = $endpoint;

      return $route;
    });

  # Add 'endpoint' helper
  $mojo->helper(
    'endpoint' => sub {
      my $c           = shift;
      my $name        = shift;
      my $given_param = shift || {};

      # Endpoint undefined
      unless (defined $endpoints{$name}) {
	$c->app->log->debug(qq{Endpoint "$name" not defined.});
	return '';
      };

      # Get url for route
      my $endpoint = $endpoints{$name};

      # Get stash or defaults hash
      my $stash_param = ref($c) eq 'Mojolicious::Controller' ?
	$c->stash : ref($c) eq 'Mojolicious' ? $c->defaults : {};

      # Interpolate template
      pos($endpoint) = 0;
      while ($endpoint =~ /\{([^\}\?}\?]+)\??\}/g) {
	# Save search position
	# Todo: Not exact!
	my $val = $1;
	my $p = pos($endpoint) - length($val) - 1;

	my $fill = undef;
	# Look in given param
	if (exists $given_param->{$val}) {
	  $fill = $given_param->{$val};
	}

	# Look in stash
	elsif (exists $stash_param->{$val}) {
	  $fill = $stash_param->{$val};
	};

	if (defined $fill) {
	  $fill = b($fill)->url_escape;
	  $endpoint =~ s/\{$val\??\}/$fill/;
	};

	# Reset search position
	# (not exact if it was optional)
	pos($endpoint) = $p + length($fill);
      };

      # Ignore optional placeholders
      if (exists $given_param->{'?'} &&
	    !defined $given_param->{'?'}) {
	for ($endpoint) {
	  s/(?<=[\&\?])[^=]+?=\{[^\?\}]+?\?\}//g;
	  s/([\?\&])\&*/$1/g;
	  s/\&$//g;
	};
      };

      return $endpoint;
    });

  # Add 'endpoints' helper
  $mojo->helper(
    'get_endpoints' => sub {
      my $c = shift;

      # Get all endpoints
      my %endpoint_hash;
      foreach (keys %endpoints) {
	$endpoint_hash{$_} = $c->endpoint($_);
      };

      # Return endpoint hash
      return \%endpoint_hash;
    });
};

1;

=pod

=head1 NAME

Mojolicious::Plugin::Util::Endpoint

=head1 SYNOPSIS

  # Mojolicious
  $self->plugin('Util::Endpoint');

  # Mojolicious::Lite
  plugin 'Util::Endpoint';

  my $route = $mojo->routes->route('/:user');

  # Set endpoint
  $route->endpoint(
           'webfinger' => {
              scheme => 'https',
              host   => 'sojolicio.us',
              route  => $route,
              query => [
                q => '{uri}'
              ]
            });

  return $self->endpoint('webfinger');
  # https://sojolicio.us/{user}?q={uri}

  $self->stash(user => 'Akron');

  return $self->endpoint('webfinger');
  # https://sojolicio.us/Akron?q={uri}

  return $self->endpoint('webfinger' => {
                            uri => 'acct:akron@sojolicio.us'
                         });
  # https://sojolicio.us/Akron?q=acct%3Aakron%40sojolicio.us


=head1 DESCRIPTION

L<Mojolicious::Plugin::Util::Endpoint> is a plugin that
allows for the simple establishement of endpoint URIs.
This is similar to the C<url_for> method of L<Mojolicious::Controller>,
but includes support for template URIs with parameters
(as used in, e.g., Host-Meta or OpenSearch).

=head1 SHORTCUTS

=head2 C<endpoint>

  my $route = $mojo->routes->route('/suggest');
  $route->endpoint('opensearch' => {
                      scheme => 'https',
                      host   => 'sojolicio.us',
                      port   => 3000,
                      query  => [
                        q     => '{searchTerms}',
                        start => '{startIndex?}'
                      ]
                    });

Establishes an endpoint defined for a service.
It accepts optional parameters C<scheme>, C<host>,
a C<port> and query parameters (C<query>).
Template parameters need curly brackets, optional
template parameters need a question mark before
the closing bracket.
Optional path placeholders are currenty not supported.

=head1 HELPER

=head2 C<endpoint>

  # In Controller:
  return $self->endpoint('webfinger');
  return $self->endpoint('webfinger', { user => 'me' } );

Returns the endpoint defined for a specific service.
It accepts additional stash values for the route.
These stash values override existing stash values from
the controller and fill the template variables.

  # In Controller:
  return $self->endpoint('opensearch');
  # https://sojolicio.us/suggest?q={searchTerms}
                                &start={startIndex?}

  return $self->endpoint('opensearch' => {
                            searchTerms => 'simpson',
                            '?' => undef
                         });
  # https://sojolicio.us/suggest?q=simpson

The special parameter C<?> can be set C<undef> to ignore
all undefined optional template parameters.

=head2 C<get_endpoints>

  # In Controller:
  my $hash = $self->get_endpoints;

  while (my ($key, $value) = each %$hash) {
    print $key, ' => ', $value, "\n";
  };

Returns a hash of all endpoints, intterpolated with the current
controller stash.

=head1 DEPENDENCIES

L<Mojolicious> (best with SSL support).

=head1 AVAILABILITY

  https://github.com/Akron/Sojolicious

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2011, Nils Diewald.

This program is free software, you can redistribute it
and/or modify it under the same terms as Perl.

=cut
