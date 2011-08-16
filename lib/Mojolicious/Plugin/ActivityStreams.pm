package Mojolicious::Plugin::ActivityStreams;
use Mojo::Base 'Mojolicious::Plugin';
use Mojolicious::Plugin::Atom;

our $as_ns;
BEGIN {
    $as_ns = 'http://activitystrea.ms/schema/1.0/';
};

# Register Plugin
sub register {
    my ($plugin, $mojo, $param) = @_;

    # Load Atom if not already loaded
    unless ($mojo->can('new_atom')) {
	$mojo->plugin('atom');
    };

    # Add 'new_activity' helper
    $mojo->helper(
	'new_activity' => sub {
	    shift; # Either Controller or App
	    return $plugin->new( shift || 'feed' );
	});

};

# Constructor
sub new {
    my $class = shift;

    # Return for register_plugin
    if (!defined $_[0]) {
	return $class if ref($class);
	return bless( {}, $class );
    }

    # Start ActivityStreams feed or entry
    elsif (@_ == 1 && index($_[0], '<') == -1) {

	my $self = Mojolicious::Plugin::Atom->new( @_ );

	bless($self,
	      (ref($class) ? ref($class) : $class).'::Document');

	$self->add_ns('activity' => $as_ns);
	return $self;

    };

    # Start document
    return Mojolicious::Plugin::ActivityStreams::Document->new(@_);
};

# Todo: Helper for registering verbs

# Document class
package Mojolicious::Plugin::ActivityStreams::Document;
use Mojolicious::Plugin::Atom;
use Mojo::Base 'Mojolicious::Plugin::Atom::Document';

our $as_ns;
BEGIN {
    $as_ns = $Mojolicious::Plugin::ActivityStreams::as_ns;
};

# New feed
sub new_feed {
    return Mojolicious::Plugin::ActivityStreams->new('feed');
};

# New entry
sub new_entry {
    return Mojolicious::Plugin::ActivityStreams->new('entry');
};

# Add ActivityStreams actor
sub add_actor {
    my $self = shift;
    my $actor = $self->SUPER::add_author( @_ );
    $actor->add('activity:object-type', $as_ns.'person');
    return $actor;
};

# Add ActivityStreams verb
sub add_verb {
    my $self = shift;

    return unless $_[0];

    # Add ns prefix if not given
    my $verb = shift;
    if (index($verb, '/') == -1) {
	$verb = $as_ns.$verb;
    };

    return $self->add('activity:verb', $verb);
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
	    $type = $as_ns.$type;
	};

	$obj->add('activity:object-type', $type);
    };

    foreach (keys %params) {
	$obj->add($_ => $params{$_});
    };

    return $obj;
};

# Add ActivityStreams object
sub add_object {
    my $self = shift;
    my $obj = $self->add('activity:object');
    $obj->_add_object_construct(@_);
    return $obj;
};

# Add ActivityStreams target
sub add_target {
    my $self = shift;
    my $target = $self->add('activity:target');
    $target->_add_object_construct(@_);
    return $target;
};

1;

__END__

=pod

=head1 NAME

Mojolicious::Plugin::ActivityStreams - ActivityStreams (Atom) Plugin

=head1 SYNOPSIS

  # Mojolicious
  $app->plugin('activity_streams');

  # Mojolicious::Lite
  plugin 'activity_streams';

  # In Controllers
  my $activity = $self->new_activity('entry');

  my $author = $activity->new_person(name => 'Fry');
  for ($activity) {
    $_->add_actor($author);
    $_->add_verb('follow');
    $_->add_object(type => 'person',
                   displayName => 'Leela');
    $_->add_title(xhtml => '<p>Fry follows Leela</p>');
  };

  my $feed = $activity->new_feed;
  $feed->add_entry($activity);

  $self->render_atom($feed);

=head1 DESCRIPTION

L<Mojolicious::Plugin::ActivityStreams> provides several functions
for the work with the Atom ActivityStreams Format as described in
L<http://activitystrea.ms/|ActivityStrea.ms>.

=head1 HELPERS

=head2 C<new_activity>

  my $activity = $self->new_activity('entry');

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

The helper C<new_activity> returns an ActivityStreams object.
It accepts the arguments C<feed> or C<entry> or all
parameters accepted by L<Mojolicious::Plugin::Serial::new>.

=head1 METHODS

L<Mojolicious::Plugin::ActivityStreams::Document> inherits all
methods from L<Mojolicious::Plugin::Atom::Document> and implements the
following new ones.

=head2 C<new_feed>

  my $feed = $activity->new_feed;

Returns a new ActivityStreams C<feed> object.

=head2 C<new_entry>

  my $entry = $activity->new_entry;

Returns a new ActivityStreams C<entry> object.

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
L<Mojolicious::Plugin::XML::Serial>,
L<Mojolicious::Plugin::Atom>.

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2011, Nils Diewald.

This program is free software, you can redistribute it
and/or modify it under the same terms as Perl.

=cut
