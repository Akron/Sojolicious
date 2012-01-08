use strict;
use warnings;

# Update Complex Value in database
sub update {
  my ($self, $entry) = @_;

  # entry has no id
  return unless exists $entry->{id};

  my $name = $self->{name};
  my $oro  = $self->{oro};
  my $id   = delete $entry->{id};

  # Begin transaction
  my $trans = $oro->txn(
    sub {

      # Update all values
      my $rv = 1;
      foreach my $key (keys %$entry) {
	my $value = $entry->{$key};

	my @pass = ($oro, $name, $id, $key, $value);

	# Normal value
	if (!ref($value)) {
	  $rv = _update_normal_value(@pass);
	}

	# Complex value
	elsif (ref($value) eq 'HASH') {
	  $rv = _update_complex_value(@pass);
	}

	# Plural value
	elsif (ref($value) eq 'ARRAY') {
	  $rv = _update_plural_value(@pass);
	};

	last unless $rv;
      };

      # Something went wrong
      return -1 unless $rv;

      # Update on Update table
      $oro->update(
	$name . '_UPDATED ' => {
	  updated => time
	} => {
	  res_id  => $id
	}) or return -1;

      # Everything went fine
      return 1;
    });

  # Everything went fine
  return $id if $trans;

  # Everything went horribly, horribly wrong!
  return undef;
};


# Update normal value
sub _update_normal_value {
  my ($oro, $name, $id, $key, $value) = @_;

  # Condition
  my $condition = {
    res_id  => $id,
    pri_key => $key
  };

  # Is defined
  if (defined $value) {

    # Todo: Do not allow creation of simple values for plural instances
    # Insert or update
    return $oro->merge($name => {
      'val' => $value
    } => $condition);
  }

  # Is not defined - delete!
  else {
    return $oro->delete($name => $condition);
  };
};


# Update complex value
sub _update_complex_value {
  my ($oro, $name, $id, $key, $value) = @_;

  my $rv = 1;
  foreach my $sec_key (keys %$value) {

    # Condition
    my $condition = {
      'res_id'  => $id,
      'pri_key' => $key,
      'sec_key' => $sec_key,
    };

    # Is defined - update or insert!
    if (defined $value->{$sec_key}) {
      $rv = $oro->merge($name => {
	'val' => $value->{$sec_key}
      } => $condition);
    }

    # Is undefined - delete!
    else {
      $rv = $oro->delete($name => $condition);
    };

    last unless $rv;
  };

  return 1 if $rv;
  return;
};


# Update plural value
sub _update_plural_value {
  my $first_element = $_[-1]->[0];

  # Update array
  if ($first_element && !ref($first_element)) {
    return _update_plural_array(@_);
  };

  # Update array of hashes
  return _update_plural_hash(@_);
};


# Update plural array
sub _update_plural_array {
  my ($oro, $name, $id, $key, $value) = @_;

  my %del_param = (
    res_id  => $id,
    pri_key => $key,
    sec_key => '%'
  );

  my @delete;

  # Update all values
  foreach my $v (@$value) {

    # Check for key prefix
    $v =~ s/^([\+\-])//;

    # Delete value
    if ($1 && $1 eq '-') {
      push(@delete, $v);
    }

    # Insert value
    else {
      # May not be necessary - so update or insert
      $oro->merge($name => {
	val => $v
      } => {
	%del_param, val => $v
      }) or return;
    };
  };

  # Delete
  $oro->delete($name => {
    %del_param,
    val => \@delete
  }) if @delete;

  return 1;
};


# Update plural hash
sub _update_plural_hash {
  my ($oro, $name, $id, $key, $value) = @_;

  my %del_param = (
    res_id  => $id,
    pri_key => $key
  );

  # Update all values
  foreach my $object (@$value) {
    return unless ref($object) eq 'HASH';

    my (%insert, %delete, %neutral);

    foreach my $sub_key (keys %$object) {

      # Check for key prefix
      $sub_key =~ s/^([\-\+])//;

      # +Create
      if ($1) {
	if ($1 eq '+') {
	  $insert{$sub_key} = $object->{'+'.$sub_key};
	}

	# -Delete
	else {
	  $delete{$sub_key} = $object->{'-'.$sub_key};
	};
      }

      # Neutral
      else {
	$neutral{$sub_key} = $object->{$sub_key};
      };
    };

    # Simplify query
    # If there are only deletes and neurals,
    # maybe it can be simplified to complete deletion
    if (!%insert && %delete && %neutral) {
      foreach my $k (keys %neutral) {
	if (exists $delete{$k}) {
	  $delete{$k} = delete $neutral{$k}
	};
      };
    };

    my @pass = ($name, $id, $key);

    # Update based on prefixes
    # Insertion
    if(%insert && !%delete && !%neutral) {

      # Abort if not successfull
      _create_plural_hash($oro, @pass, \%insert) or return;
    }

    # Deletion
    elsif (%delete && !%insert && !%neutral) {

      my ($sql, $bind_param) = _sql_obj('delete', @pass, \%delete);

      my ($rv) = $oro->prep_and_exec($sql, $bind_param);
      return unless $rv;

    }

    # No strict insert or delete
    # Todo: Better oop
    else {
      return unless
	_update_plural_hash_values(
	  $oro,
	  @pass,
	  \%insert,
	  \%delete,
	  \%neutral);
    };
  };

  # Everything went fine
  return 1;
};


# Update values in a plural hash
sub _update_plural_hash_values {
  my ($oro, $name, $id, $key, $insert, $delete, $neutral) = @_;

  # Add conditional deletes
  my ($k, $v);
  while (($k, $v) = each %$delete) {
    $neutral->{$k} = $v if defined $v;
  };

  # Generate sql
  my ($sql, $bind_param) = _sql_obj('find', $name, $id, $key, $neutral);

  # Prepare and execute
  my ($rv, $sth) = $oro->prep_and_exec($sql, $bind_param, 'cached');

  # Todo: Check for rv

  # Fetch all matching ids
  my @matches = map($_->[0],  @{$sth->fetchall_arrayref});

  # Update all matching objects
  my $obj_id;
  foreach $obj_id (@matches) {

    my %condition = (
      res_id  => $id,
      pri_key => $key,
      obj_id  => $obj_id
    );

    # Single line inserts
    foreach $k (keys %$insert) {
      $oro->merge($name => {
	val => $insert->{$k}
      } => {
	%condition,
	sec_key => $k
      }) or return;
    };

    # Single line deletes
    foreach my $k (keys %$delete) {
      $oro->delete($name => {
	%condition,
	sec_key => $k
      });
    };
  };
  return 1;
};


# Delete or detect plural object
sub _sql_obj {
  my ($action, $name, $id, $key, $param) = @_;

  my (@parameter, @table, @where);

  foreach (1.. scalar(keys %$param)) {
    push(@table, 'Table' . $_);
  };

  my $sql;

  # delete object
  if ($action eq 'delete') {
    $sql = 'DELETE FROM ' . $name . ' WHERE id IN ' .
           '(SELECT Show.id ';
    push(@where, 'Table1.obj_id IN (Show.obj_id, Show.id)');
    push(@where, 'Table1.obj_id = ' . $_ . '.obj_id') foreach @table[1..$#table];
  }

  # find obj_id
  elsif ($action eq 'find') {
    $sql = 'SELECT DISTINCT Show.obj_id ';
    push(@where, 'Show.obj_id NOT NULL');
    push(@where, 'Show.obj_id = ' . $_ . '.obj_id') foreach @table;
  }

  else {
    return;
  };

  # from clause
  $sql .= ' FROM '.$name.' AS Show ';
  $sql .= ', Resource AS ' . $_ . ' ' foreach @table;

  push(@where, 'Show.res_id  = ?',
               'Show.pri_key = ?');
  push(@parameter, $id, $key);

  foreach (@table) {
    push(@where, $_ . '.res_id = ?');
    push(@parameter, $id);
  };

  foreach my $param_key (keys %$param) {
    my $t = shift(@table);
    push(@where, $t . '.sec_key = ?',
	         $t . '.val = ?');
    push(@parameter, $param_key, $param->{$param_key});
  };

  # where clause
  $sql .= ' WHERE '.join(' AND ', @where);

  # Close subselection if delete
  $sql .= ')' if $action eq 'delete';
  return ($sql, \@parameter);
};

1;

__END__

# For documentation, see Sojolicious::ComplexValues.
