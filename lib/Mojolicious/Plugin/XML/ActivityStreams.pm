package Mojolicious::Plugin::XML::ActivityStreams;
use Mojo::Base 'Mojolicious::Plugin::XML::Base';

our $PREFIX = 'activity';
our $NAMESPACE = 'http://activitystrea.ms/schema/1.0/';

# Todo - support json
sub new {  warn 'Only use as an extension to Atom'; 0; };

# Add ActivityStreams actor
sub add_actor {
    my $self  = shift;
    my $actor = $self->add_author( @_ );
    $actor->add('object-type', $NAMESPACE . 'person');
    return $actor;
};

# Add ActivityStreams verb
sub add_verb {
    my $self = shift;

    return unless $_[0];

    # Add ns prefix if not given
    my $verb = shift;
    if (index($verb, '/') == -1) {
	$verb = $NAMESPACE . $verb;
    };

    return $self->add('verb', $verb);
};

# add ActivityStreams object construct
sub _add_object_construct {
    my $obj = shift;
    my %params = @_;

    $obj->add_id( delete $params{id} ) if exists $params{id};

    if (exists $params{type}) {

	my $type = delete $params{type};

	# Add ns prefix if not given
	if (index($type, '/') == -1) {
	    $type = $NAMESPACE . lc($type);
	};

	$obj->add('object-type', $type);
    };

    foreach (keys %params) {
	$obj->add('-' . $_ => $params{$_});
    };

    return $obj;
};

# Add ActivityStreams object
sub add_object {
    my $self = shift;
    my $obj = $self->add('object');
    $obj->_add_object_construct(@_);
    return $obj;
};

# Add ActivityStreams target
sub add_target {
    my $self = shift;
    my $target = $self->add('target');
    $target->_add_object_construct(@_);
    return $target;
};

1;
__END__

=pod

=head1 NAME

Mojolicious::Plugin::XML::ActivityStreams - ActivityStreams (Atom) Plugin

=head1 SYNOPSIS

  # Mojolicious
  $app->plugin('XML' => {
    new_activity => ['Atom','ActivityStreams']
  });

  # Mojolicious::Lite
  plugin 'XML' => {
    new_activity => ['Atom','ActivityStreams']
  };

  # In Controllers
  my $activity = $self->new_activity(<<'ACTIVITY');
  <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
  <entry xmlns="http://www.w3.org/2005/Atom"
         xmlns:activity="http://activitystrea.ms/schema/1.0/">
    <author>
      <name>Fry</name>
      <activity:object-type>person</activity:object-type>
    </author>
    <activity:verb>follow</activity:verb>
    <activity:object>
      <activity:object-type>person</activity:object-type>
      <displayName>Leela</displayName>
    </activity:object>
    <title type="xhtml">
      <div xmlns="http://www.w3.org/1999/xhtml"><p>Fry follows Leela</p></div>
    </title>
  </entry>
  ACTIVITY

  my $activity = $self->new_activity('entry');

  my $author = $activity->new_person(name => 'Fry');
  for ($activity) {
    $_->add_actor($author);
    $_->add_verb('follow');
    $_->add_object(type => 'person',
                   displayName => 'Leela');
    $_->add_title(xhtml => '<p>Fry follows Leela</p>');
  };

  $self->render_xml($activity);

=head1 DESCRIPTION

L<Mojolicious::Plugin::XML::ActivityStreams> is an extension
for L<Mojolicious::Plugin::XML::Atom> and provides several functions
for the work with the Atom ActivityStreams Format as described in
L<http://activitystrea.ms/|ActivityStrea.ms>.

=head1 HELPERS

=head1 METHODS

=head2 C<add_actor>

  my $person = $activity->new_person( name => 'Bender',
                                      uri  => 'acct:bender@example.org');
  my $actor = $atom->add_actor($person);

Adds actor information to the ActivityStreams object.
Accepts a person construct (see L<new_person> in
L<Mojolicious::Plugin::Atom::Document>) or the
parameters accepted by L<new_person>.

=head2 C<add_verb>

  $activity->add_verb('follow');

Adds verb information to the ActivityStreams object.
Accepts a verb string.

=head2 C<add_object>

  $activity->add_object( type => 'person',
                         displayName => 'Leela' );

Adds object information to the ActivityStreams object.
Accepts various parameters depending on the object's type.

=head2 C<add_target>

  $activity->add_target( type => 'person',
                         displayName => 'Fry' );

Adds target information to the ActivityStreams object.
Accepts various parameters depending on the object's type.

=head1 DEPENDENCIES

L<Mojolicious>,
L<Mojolicious::Plugin::XML>,
L<Mojolicious::Plugin::XML::Atom>.

=head1 AVAILABILITY

  https://github.com/Akron/Sojolicious

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2011, Nils Diewald.

This program is free software, you can redistribute it
and/or modify it under the same terms as Perl.

=cut
