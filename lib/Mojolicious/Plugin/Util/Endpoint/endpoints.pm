package Mojolicious::Plugin::Util::Endpoint::endpoints;
use Mojo::Base 'Mojolicious::Command';

use Getopt::Long qw/GetOptions :config no_auto_abbrev no_ignore_case/;

has description => "Show available endpoints.\n";
has usage       => <<"EOF";
usage: $0 endpoints

EOF


# Run oro_init
sub run {
  my $self = shift;

  # Options
  local @ARGV = @_;

  my $c = Mojolicious::Controller->new;
  $c->app($self->app);

  # Get endpoints
  my $endpoints = $c->get_endpoints;

  # No endpoints
  return unless $endpoints;

  # Print all endpoints
  while (my ($name, $path) = each %$endpoints) {
    printf " %-20s %s\n", '"' . $name . '"', $path;
  };
  print "\n";

  return;
}


1;


__END__

=pod

=head1 NAME

Mojolicious::Plugin::Util::Endpoint::endpoints - Show endpoints

=head1 SYNOPSIS

  use Mojolicious::Plugin::Util::Endpoint::endpoints;

  my $ep = Mojolicious::Plugin::Util::Endpoint::endpoints->new;
  $ep->run;

=head1 DESCRIPTION

L<Mojolicious::Plugin::Util::Endpoint::endpoints> shows all
endpoints established by L<Mojolicious::Plugin::Util::Endpoint>.

=head1 ATTRIBUTES

L<Mojolicious::Plugin::Util::Endpoint::endpoints> inherits all
attributes from L<Mojo::Command> and implements the following
new ones.

=head2 C<description>

  my $description = $ep->description;
  $ep            = $ep->description('Foo!');

Short description of this command, used for the command list.

=head2 C<usage>

  my $usage = $ep->usage;
  $ep       = $ep->usage('Foo!');

Usage information for this command, used for the help screen.

=head1 METHODS

L<Mojolicious::Plugin::Util::Endpoint::endpoints> inherits all
methods from L<Mojo::Command> and implements the following new ones.

=head2 C<run>

  $oro_init->run;

Run this command.


=head1 DEPENDENCIES

L<Mojolicious>,
L<Mojolicious::Plugin::Util::Endpoint>.


=head1 AVAILABILITY

  https://github.com/Akron/Sojolicious


=head1 COPYRIGHT AND LICENSE

Copyright (C) 2012, Nils Diewald.

This program is free software, you can redistribute it
and/or modify it under the same terms as Perl.

The documentation is based on L<Mojolicious::Command::eval>,
written by Sebastian Riedel.

=cut
