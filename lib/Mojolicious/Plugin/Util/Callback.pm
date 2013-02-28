package Mojolicious::Plugin::Util::Callback;
use Mojo::Base 'Mojolicious::Plugin';

my %callback;

# Register the plugin
sub register {
  my ($plugin, $mojo, $param) = @_;

  $mojo->helper(
    callback => sub {
      my $c = shift;
      my $name = shift;

      # Establish callback
      if (ref $_[0] && ref $_[0] eq 'CODE') {
	my $cb = shift;
	my $once = $_[0] && $_[0] eq '-once' ? 1 : 0;

	if (exists $callback{$name} && $callback{$name}->[1]) {
	  $mojo->log->debug(
	    qq{No allowance to redefine callback "$name"}
	  );

	  # Return nothing
	  return;
	};

	# Establish callback
	$callback{$name} = [$cb, $once];
      }

      # Call callback
      else {
	if (exists $callback{$name}) {
	  return $callback{$name}->[0]->($c, @_);
	};

	# Return nothing
	return;
      };
    }
  );
};

1;

__END__

=pod

=head1 NAME

Mojolicious::Plugin::Util::Callback - Reverse helpers for Mojolicious


=head1 SYNOPSIS

  # Mojolicious
  $app->plugin('Util::Callback');

  # Mojolicious::Lite
  plugin 'Util::Callback';

  # In controller or app
  $c->callback(get_cached_profile => sub {
    my ($c, $name) = @_;
    return $c->cache->get( $name );
  });

  # In Plugin
  my $profile = $c->callback(
    get_cached_profile => 'Akron'
  );


=head1 DESCRIPTION

Callbacks are similar to helpers, with a slightly
different semantic.
While helpers are usually established by plugins
and called by controllers, callbacks are
usually called by plugins and established
in a controller or by other plugins.

A typical usecase is the database agnostic
access to caching via plugins.


=head1 HELPERS

=head2 callback

  # Establish callback
  $c->callback(get_cached_profile => sub {
    my ($c, $name) = @_;
    return $c->cache->get( $name );
  }, -once);

  # Call a callback
  my $profile = $c->callback(get_cached_profile => 'Akron');

Establish or call a callback.
To call a callback, just pass the name and all parameters
to the helper.
To establish a callback, pass the name and a code reference
to release to the helper. The arguments of the callback
function will be the controller object followed by all
passed parameters from the call.

An additional C<-once> flag when establishing indicates,
that the callback is not allowed to be redefined later.

If there is no callback defined for a certain name,
C<undef> is returned.


=head1 AVAILABILITY

  https://github.com/Akron/Sojolicious


=head1 COPYRIGHT AND LICENSE

Copyright (C) 2013, L<Nils Diewald|http://nils-diewald.de/>.

This program is free software, you can redistribute it
and/or modify it under the same terms as Perl.

=cut
