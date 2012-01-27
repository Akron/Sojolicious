use strict;
use warnings;

# Add Hash to Database
sub create {
  my ($self, $entry) = @_;

  my $oro  = $self->{oro};
  my $name = $self->{name};
  my $dbh  = $oro->dbh;

  # Begin transaction
  my $id;
  my $trans = $oro->txn(
    sub {

      # Slow but securely returns the correct id
      $dbh->do(<<"MAX_ID") or return -1;
INSERT INTO $name
  (pri_key, res_id, val)
SELECT "id",
  ifnull((SELECT MAX(res_id) FROM $name),0) + 1,
  ifnull((SELECT MAX(res_id) FROM $name),0) + 1
MAX_ID

      my ($rv, $sth) = $oro->prep_and_exec(
	'SELECT res_id FROM ' . $name .
	  ' WHERE id = last_insert_rowid()');

      return -1 unless $rv;

      $id = ($sth->fetchrow_array);

      # Set publish and update time in entry
      $entry->{published} =
	$entry->{updated} = time;

      # Store values
      $rv = 1;
      foreach my $key (keys %$entry) {
	my $value = $entry->{$key};

	next unless $value;

	# Todo: Better oop
	my @pass = ($oro, $name, $id, $key, $value);

	# Normal value
	if (!ref($value)) {
	  $rv = _create_normal_value(@pass);
	}

	# Complex value
	elsif (ref($value) eq 'HASH') {
	  $rv = _create_complex_value(@pass);
	}

	# Plural value
	elsif (ref($value) eq 'ARRAY') {
	  $rv = _create_plural_value(@pass);
	};

	last unless $rv;
      };

      return -1 unless $rv;

      # Insert into updated table
      $oro->insert(
	$name . '_UPDATED ' => {
	  res_id  => $id,
	  updated => $entry->{updated}
	}) or return -1;

      return;
    });

  # Return id if transaction was successfull
  return $id if $trans;

  # Everything went horribly, horribly wrong!
  return undef;
};


# Create normal value
sub _create_normal_value {
  return shift->insert(
    $_[0] => {
      res_id  => $_[1],
      pri_key => $_[2],
      val     => $_[3]
    });
};


# Create complex value
sub _create_complex_value {
  my ($oro, $name, $id, $key, $value) = @_;

  # Insert values as multiple inserts
  $oro->insert($name =>
		 [
		   [res_id => $id],
		   [pri_key => $key],
		   'sec_key', 'val'
		 ] => map { [ $_, $value->{$_} ] } keys %$value
	       ) or return;

  return 1;
};


# Create plural value
sub _create_plural_value {
  my ($oro, $name, $id, $key, $value) = @_;

  my @pass = ($oro, $name, $id, $key);

  foreach my $object (@$value) {

    # Is hashref
    if (ref($object)) {
      _create_plural_hash(@pass, $object) or return;
    }

    # Is array
    else {
      _create_plural_array(@pass, $object) or return;
    };
  };

  return 1;
};


# Create plural hash
sub _create_plural_hash {
  my ($oro, $name, $id, $key, $object) = @_;

  # Insert init for plural hash
  $oro->insert(
    $name => {
      res_id  => $id,
      pri_key => $key
    }) or return;

  # Get obj_id for plural hash
  my $obj_id = $oro->last_insert_id;

  # Insert values as multiple inserts
  $oro->insert(
    $name => [
      [res_id => $id],
      [obj_id => $obj_id],
      [pri_key => $key],
      'sec_key', 'val'
    ] => map { [ $_, $object->{$_} ] } keys %$object
  ) or return;

  return 1;
};


# Create plural array
sub _create_plural_array {

  # Return false if unable to insert
  $_[0]->insert(
    $_[1] => {
      res_id   => $_[2],
      pri_key  => $_[3],
      sec_key  => '%',
      val      => $_[4]
    }) or return;

  return 1;
};

1;

__END__

# For documentation, see Sojolicious::ComplexValues.
