package Mojolicious::Plugin::Oro::oro_init;
use Mojo::Base 'Mojolicious::Command';

use Getopt::Long qw/GetOptions :config no_auto_abbrev no_ignore_case/;

has description => "Initialize all associated Oro databases.\n";
has usage       => <<"EOF";
usage: $0 oro_init [DATABASES]

  perl app.pl oro_init
  perl app.pl oro_init 'default' 'Books'

Give no list for all associated Oro handles.
Give a list of Oro handles to initialize.

EOF


# Run oro_init
sub run {
  my $self = shift;

  # Options
  local @ARGV = @_;

  my $app = $self->app;

  my $databases = $app->attr('oro_handles') || {};

  @ARGV = keys %$databases unless @ARGV;

  foreach my $name (@ARGV) {

    # Initialize database
    if (exists $databases->{$name}) {
      $app->plugins->emit_hook(
	'on_' . ($name ne 'default' ? $name . '_' : '') . 'oro_init' =>
	  $databases->{$name}
	);
    }

    # Database does not exist
    else {
      $app->log->warn("Database $name does not exist.");
    };
  };

  return 1;
}


1;


__END__

=pod

=head1 NAME

Mojolicious::Plugin::Oro::oro_init - Initialize Oro Databases

=head1 SYNOPSIS

  use Mojolicious::Plugin::Oro::oro_init;

  my $oro_init = Mojolicious::Plugin::Oro::oro_init->new;
  $oro_init->run;

=head1 DESCRIPTION

L<Mojolicious::Plugin::Oro::oro_init> initializes all Oro
databases associated with L<Mojolicious::Plugin::Oro>.

=head1 ATTRIBUTES

L<Mojolicious::Plugin::Oro::oro_init> inherits all attributes
from L<Mojo::Command> and implements the following new ones.

=head2 C<description>

  my $description = $oro_init->description;
  $oro_init       = $oro_init->description('Foo!');

Short description of this command, used for the command list.

=head2 C<usage>

  my $usage = $oro_init->usage;
  $oro_init = $oro_init->usage('Foo!');

Usage information for this command, used for the help screen.

=head1 METHODS

L<Mojolicious::Plugin::Oro::oro_init> inherits all methods from
L<Mojo::Command> and implements the following new ones.

=head2 C<run>

  $oro_init->run;

Run this command.


=head1 DEPENDENCIES

L<Mojolicious>,
L<Sojolicious::Oro>.


=head1 AVAILABILITY

  https://github.com/Akron/Sojolicious


=head1 COPYRIGHT AND LICENSE

Copyright (C) 2012, Nils Diewald.

This program is free software, you can redistribute it
and/or modify it under the same terms as Perl.

The documentation is based on L<Mojolicious::Command::eval>,
written by Sebastian Riedel.

=cut
