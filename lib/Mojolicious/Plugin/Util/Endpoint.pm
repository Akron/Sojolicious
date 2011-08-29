package Mojolicious::Plugin::Util::Endpoint;
use Mojo::Base 'Mojolicious::Plugin';
use Mojo::URL;

sub register {
    my ($plugin, $mojo, $param) = @_;

    # Establish 'endpoint' shortcut
    $mojo->routes->add_shortcut(
	'endpoint' => sub {
	    my ($route, $name, $param) = @_;

	    # Endpoint already defined
	    if ($mojo->defaults('endpoint.'.$name)) {
		$mojo->log->error(qq{Route endpoint "$name" already defined.});
		return $route;
	    };

	    # Route defined
	    $route->name($name);

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
		elsif (exists $param->{secure}) {
		    $mojo->log->warn('secure is deprecated!');
		    $_->scheme( $param->{secure} ? 'https' : 'http' );
		}

		# Defaults to http
		else {
		    $_->scheme( 'http' );
		};

		# Set query parameter
		if (defined $param->{query}) {
		    $_->query( $param->{query} );
		};
	    };

	    my $endpoint = $endpoint_url->to_string;
	    $endpoint =~ s/\%7B(.+?)\%7D/{$1}/g;

	    # Set to stash
	    $mojo->defaults('endpoint.'.$name => $endpoint);

	    return $route;
	});
    

    # Establish 'endpoint' helper
    $mojo->helper(
	'endpoint' => sub {
	    my $c = shift; # c or mojo
	    my $name = shift;
	    
	    # Endpoint undefined
	    unless (defined $mojo->defaults('endpoint.'.$name)) {
		$c->app->log->error(qq{Endpoint "$name" not defined.});
		return '';
	    };

	    # get url for route
	    my $endpoint = $mojo->defaults('endpoint.' . $name);;

	    # Get parameter from stash
	    my %query_param;
	    if (ref($c) eq 'Mojolicious::Controller') {
		%query_param = %{ $c->stash };
	    };
	    
	    # Get parameter from given data
	    if (my $given_param = shift) {
		while (my ($key, $value) = each %$given_param) {
		    $query_param{$key} = $value;
		};
	    };
	    	       
	    # Interpolate template
	    pos($endpoint) = 0;
	    while ($endpoint =~ /{([^}]+)}/g) {
		my $p = pos($endpoint) - length($1) + 1;
		my $val = $1;
		if (exists $query_param{$val}) {
		    $endpoint =~ s/\{$val\}/$query_param{$val}/;
		};
		pos($endpoint) = $p;
	    };
	    
	    return $endpoint;
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

  # In Controllers

  my $route = $mojo->routes->route('/:user');

  # Set endpoint
  $route->endpoint(
           'path' => {
              scheme => 'https',
              host   => 'sojolicio.us',
              route  => $route,
              query => [
                q => '{uri}'
              ]
            });

  $self->stash(user => 'Akron');

  # Get endpoint
  print $self->endpoint('path');
  # https://sojolicio.us/Akron?q={uri}

  print $self->endpoint('path', { uri => 'name'});
  # https://sojolicio.us/Akron?q=name


=head1 DESCRIPTION

L<Mojolicious::Plugin::Util::Endpoint> is a plugin to
allow for simple establishement of endpoint URIs.
This is similar to the C<url_for> method of L<Mojolicious::Controller>,
but includes support for template urls with parameters
as used in, e.g., Opensearch.

=head1 SHORTCUTS

=head2 C<endpoint>

  my $route = $mojo->routes->route('/:user/webfinger');
  $route->endpoint('webfinger' => {
                      scheme => 'https',
                      host   => 'sojolicio.us',
                      port   => 3000,
                      query  => [ q => '{uri}' ]
                    });

Stores an endpoint defined for a service. It accepts optional
parameters C<scheme>, C<host>, a C<port> and 
query parameters (C<query>).

=head1 HELPER

=head2 C<endpoint>

  # In Controller:
  return $self->endpoint('webfinger');
  return $self->endpoint('webfinger', { user => 'me' } );

Returns the endpoint defined for a specific service.
It accepts additional stash values for the route. These
stash values override existing stash values from the
controller and fill the template variables.

=head1 DEPENDENCIES

L<Mojolicious> (best with SSL support).

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2011, Nils Diewald.

This program is free software, you can redistribute it
and/or modify it under the same terms as Perl.

=cut
