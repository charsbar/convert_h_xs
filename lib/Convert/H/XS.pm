package Convert::H::XS;

use strict;
use warnings;
use Carp;
use File::Spec::Functions qw/abs2rel rel2abs/;
use Text::Balanced;

our $VERSION = '0.01';

sub new {
  my ($class, %args) = @_;

  bless \%args, $class;
}

sub preprocess {
  my ($self, $target) = @_;

  my $source = $self->_get_source($target);

  my $stash = $self->{stash} ||= {};

  # remove comments
  # (special cases like #include <a/*b> can probably be ignored)
  $source =~ s{(?:
      /\*.*?\*/ # C like comments
    | //[^\n]*  # C++ like comments
  )+}{}gxs;

  # EOL backslashes
  $source =~ s{\s*\\\s*\n\s*}{ }xsg;

  my @lines;
  for my $line (split /\n/, $source) {
    if ($line =~ s/^\s*#\s*(\w+)\s*//s) {
      my $directive = $1;
      if ($directive eq 'define') {
        $line =~ s/^(\w+)//s or next;
        my $name = $1;

        if (substr($line, 0, 1) eq '(') {
          my ($args, $definition) = _extract($line, '(');
          push @{ $stash->{define_with_args} ||= [] }, ["$name$args", _trim($definition)];
        }
        else {
          push @{ $stash->{define} ||= [] }, [$name, _trim($line)];
        }
      }
      elsif ($directive eq 'include') {
        if ($line =~ /<([^>]+)>/s) {
          push @{ $stash->{include_system} ||= [] }, $1;
        }
        elsif ($line =~ /"([^"]+)"/s) {
          push @{ $stash->{include_user} ||= [] }, $1;

          # XXX: merge stashs from included headers?
        }
        # ignore computed includes
      }
      next;
    }
    next if $line =~ /^\s*(?:#|$)/;
    push @lines, $line;
  }

  return join "\n", @lines;
}

sub process {
  my ($self, $target) = @_;

  my $source = $self->_get_source($target);

  if ($source =~ /#/) {
    $source = $self->preprocess(\$source);
  }

  my $stash = $self->{stash} ||= {};

  while(1) {
    my ($block, $after, $before) = _extract($source, '{', '[^{]*');
    last unless $block;
    if ($before =~ s/extern\s+"[^"]+"\s*$//) {
      $source = $before._trim($block, '{}').$after;
      next;
    }
    if ($before =~ s/\s*typedef\s+enum\s*$//s) {
      $after =~ s/^\s*(\w+)\s*;//;
      my $name = $1;
      my $enum_ct = -1;
      my @items = map {
        my ($key, $value) = split /\s*=\s*/;
        $enum_ct = defined $value ? $value : $enum_ct + 1;
        [$key, $enum_ct];
      }
      split /\s*,\s*/s, _trim($block, '{}');
      $stash->{typedef_enum}{$name} = \@items;
    }
    elsif ($before =~ s/\s*typedef\s+(struct|union)\s+\w*\s*$//s) {
      my $type = $1;
      $after =~ s/^\s*(\w+)\s*;//;
      my $name = $1;
      my @items = _split_struct_items(_trim($block, '{}'));
      $stash->{"typedef_".$type}{$name} = \@items;
    }
    elsif ($before =~ s/\s*(struct|union)\s+(\w+)\s*$//s) {
      my ($type, $name) = ($1, $2);
      $after =~ s/^\s*;//;
      my @items = _split_struct_items(_trim($block, '{}'));
      $stash->{$type}{$name} = \@items;
    }
    $source = "$before$after";
  }

  while ($source =~ s/typedef\s+(struct|union)\s+([^\s;]+)\s+([^;]+);//s) {
    $stash->{"typedef_".$1}{$3} = $2;
  }

  while ($source =~ s/typedef\s+([^;]+);//s) {
    my $def = $1;
    my @tokens;
    if ($def =~ /\(/) {
      my $tmp = '';
      while(1) {
        my ($block, $after, $before) = _extract($def, '(', '[^\(]*');
        if ($block) {
          $block =~ s/\s+/\0/g;
          $tmp .= "$before$block";
          $def = $after;
        }
        else {
          $tmp .= $after;
          last;
        }
      }
      @tokens = map { s/\0/ /g; $_ } split /\s+/s, $tmp;
    }
    else {
      @tokens = split /\s+/s, $def;
    }
    my $name = pop @tokens;
    $stash->{typedef}{$name} = join ' ', @tokens;
  }

  while(1) {
    my ($block, $after, $before) = _extract($source, '(', '[^\(]*');
    last unless $block;
    if ($before =~ s/(^|;)\s*([^;]+?)\s*(\w+)$/$1/s) {
      my ($type, $name) = ($2, $3);
      $after =~ s/^\s*;//s;
      my @args = _split_func_args(_trim($block, '()'));
      $stash->{function}{$name} = [$type, \@args];
    }
    $source = "$before$after";
  }

  $source;
}

sub write_all {
  my ($self, $callbacks) = @_;

  my $dir = $self->_dir;
  $callbacks ||= {};

  $self->write_functions("$dir/functions.xs.inc", $callbacks->{functions});
  $self->write_constants("$dir/constants.xs.inc", $callbacks->{constants});
  $self->write_enum_constants("$dir/enum_constants.xs.inc", $callbacks->{enum_constants});

  if (my $package = $self->{package}) {
    my ($basename) = $package =~ /(?:^|::)(\w+)$/;
    $self->write_xs("$basename.xs");
  }
}

sub write_functions {
  my ($self, $file, $callback) = @_;

  unless (defined $file) {
    $file = $self->_dir . "/functions.xs.inc";
  }

  open my $fh, '>', $file or croak "Failed to open $file: $!";

  $self->_write_do_not_edit_warning($fh);

  my %funcs =  %{$self->{stash}{function} || {}};
  while(%funcs) {
    %funcs = _write_functions($fh, $callback, \%funcs);
  }
  $self->{incfile}{functions} = $file;
}

sub _write_do_not_edit_warning {
  my ($self, $fh) = @_;

  print $fh <<"EOT";
### This file is generated by Convert::H::XS version $Convert::H::XS::VERSION.
### DO NOT EDIT THIS FILE. ANY CHANGES WILL BE LOST!

EOT
}

sub _write_functions {
  my ($fh, $callback, $funcs) = @_;

  my %callbacks;
  for my $name (sort keys %$funcs) {
    my ($type, $args) = @{ $funcs->{$name} || [] };
    if ($callback) {
      my @res = $callback->($type, $name, $args);
      next if @res == 0;
      ($type, $name, $args) = @res;
    }
    my ($cb_id, $arg_id) = ("", 0);
    print $fh "$type\n$name(",
      join(", ", 
        map {
          if ($_ ne '...' and ($_ =~ /\*$/ or $_ !~ /\s/)) {
            $_ .= " arg".$arg_id++;
          }
          $_;
        }
        map {
          !ref $_ ? $_ : do {
            my $pointer = _trim($_->[1], '()');
            $pointer =~ s/^\s*\*\s*//;
            my $cb_name = $name . ($pointer ? "_$pointer" : "_cb" . $cb_id++);
            $callbacks{$cb_name} = [$_->[0], $_->[2]];
            "$_->[0] $cb_name";
          };
        } @{$args || []}
      ),
    ")\n\n";
  }
  %callbacks;
}

sub write_constants {
  my ($self, $file, $callback) = @_;

  my @consts = grep { $_->[0] =~ /^[A-Z][A-Z0-9_]+$/ }
               @{$self->{stash}{define} || []};

  @consts = grep { $callback->(@{$_}) } @consts if $callback;

  return unless @consts;

  $self->{incfile}{define} = $file ||= $self->_dir . "/constants.xs.inc";

  $self->_write_constants($file, \@consts);
}

sub write_enum_constants {
  my ($self, $file, $callback) = @_;

  my %enum = %{ $self->{stash}{typedef_enum} || {}};

  my @consts;
  if ($callback) {
    for my $key (keys %enum) {
      push @consts, grep { $callback->(@{$_}) } @{$enum{$key}};
    }
  }
  else {
    push @consts, @{$enum{$_}} for keys %enum;
  }
  return unless @consts;

  $self->{incfile}{typedef_enum} = $file ||= $self->_dir . "/enum_constants.xs.inc";

  $self->_write_constants($file, \@consts);
}

sub _write_constants {
  my ($self, $file, $consts) = @_;

  open my $fh, '>', $file or croak "Failed to open $file: $!";

  $self->_write_do_not_edit_warning($fh);

  for (@$consts) {
    my ($name, $value) = @{$_};
    my $type = ($value =~ /^(["']).+\1$/) ? "const char*" : "IV";
    print $fh <<"XS";
$type
${name}()
  CODE:
    RETVAL = $name;
  OUTPUT:
    RETVAL

XS
  }
}

sub write_xs {
  my ($self, $file) = @_;

  if (-e $file and !$self->{force}) {
    croak "$file already exists; use 'force' option to override.";
  }
  my ($parent) = $file =~ m|^(.+)[^\\/]+$|;

  my $package = $self->{package} or croak "'package' is required";

  open my $fh, '>', $file or croak "Failed to open $file: $!";

  print $fh <<"END";
#include <EXTERN.h>
#include <perl.h>
#include <XSUB.h>
END

  print $fh <<"END" if $self->{use_ppport};
#include "ppport.h"
END

  for my $h_file (@{$self->{h_files} || []}) {
    # TODO: fix include directory
    print $fh <<"END";
#include "$h_file"
END
  }

  print $fh <<"END";

MODULE = $package  PACKAGE = $package

PROTOTYPES: DISABLE

END

  for my $key (keys %{$self->{incfile} || {}}) {
    my $incfile = $self->{incfile}{$key};
    my $relpath = abs2rel(rel2abs($incfile), $parent);
    $relpath =~ s|\\|/|g;
    print $fh <<"END";
INCLUDE: $relpath
END
  }
}

sub _get_source {
  my ($self, $target) = @_;

  my $source;
  if (ref $target eq ref \"") {
    $source = $$target;
  }
  else {
    push @{$self->{h_files} ||= []}, $target;
    open my $fh, '<', $target or croak "Failed to open $target: $!";
    $source = do { local $/; <$fh> };
    $self->{package} ||= do {
      (my $file = $target) =~ s/\.h$//;
      $file =~ s!\\!/!g;
      $file =~ s/^.+://;
      $file =~ s!^.+/!! if $file =~ m!^/!;
      join '::', map { ucfirst $_ }
                 grep { !/^\./ }
                 split '/', $file;
    };
  }
  if ($self->{encoding}) {
    require Encode;
    $source = Encode::decode($self->{encoding}, $source);
  }

  $source;
}

sub _dir {
  my $self = shift;
  my $dir = $self->{xs_dir} || '.';
  unless (-d $dir) {
    require File::Path;
    File::Path::mkpath $dir;
  }
  $dir;
}

# utils

sub _extract {
  my ($text, $delim, $pattern) = @_;
  Text::Balanced::extract_bracketed($text, $delim, $pattern);
}

sub _trim {
  if ($_[1]) {
    my ($start, $end) = (substr($_[1], 0, 1), substr($_[1], -1, 1));
    $_[0] =~ s/^\s*\Q$start\E//s;
    $_[0] =~ s/\Q$end\E\s*$//s;
  }
  $_[0] =~ s/^\s+//s;
  $_[0] =~ s/\s+$//s;
  $_[0];
}

sub _split_struct_items {
  my $block = shift;

  my $tmp = '';
  while(1) {
    # may have other structs/unions in it
    my ($inner, $after, $before) = _extract($block, '{', '[^{]*');
    if ($inner) {
      $inner =~ s/;/\0/g;
      $tmp .= "$before$inner";
      $block = $after;
    }
    else {
      $tmp .= $after;
      last;
    }
  }
  map { !/\(/ ? $_ : _split_callback_args($_) }
  map { s/\0/;/g; $_ }
  split /\s*;\s*/s, $tmp;
}

sub _split_callback_args {
  my $block = shift;

  my $tmp = '';
  my ($pointer, $args, $type) = _extract($block, '(', '[^(]*');
  $type =~ s/\s*$//s;
  $args =~ s/^\s*//s;
  [$type, $pointer, [_split_func_args(_trim($args, '()'))]];
}

sub _split_func_args {
  my $block = shift;

  my $tmp = '';
  while(1) {
    # may have callback definition in it
    my ($inner, $after, $before) = _extract($block, '(', '[^(]*');
    if ($inner) {
      $inner =~ s/\s*,\s*/\0/gs;
      $tmp .= "$before$inner";
      $block = $after;
    }
    else {
      $tmp .= $after;
      last;
    }
  }
  map { !/\(/ ? $_ : _split_callback_args($_) }
  map { s/\0/, /g; $_ }
  split /\s*,\s*/s, $tmp;
}

1;

__END__

=head1 NAME

Convert::H::XS - process a C header file to write xs snippets

=head1 SYNOPSIS

  use Convert::H::XS;

  my $converter = Convert::H::XS->new(
    package => 'Foo::Bar',
  );

  # collect information from .h file
  $converter->process("foo/bar.h");

  # write XS interfaces with the info
  $converter->write_functions("xs/functions.xs.inc", sub {
    my ($type, $name, $args) = @_;

    # No XS interface is needed unless public
    return unless $type =~ s/\s*PUBLIC_API\s+//s;

    # Want to tweak the interface name?
    $name =~ s/^c_prefix_/xs_/;

    if ($name eq 'xs_func') {
      # You can tweak function arguments.
      # "int *" is probably to get some value from the function.
      # Marking the arg with "OUT" helps the XS converter (xsubpp).
      $args->[1] =~ s/^int \*/OUT int /;
    }

    # Everything is tweaked. Return them all to replace.
    return ($type, $name, $args);
  });

  $converter->write_constants("xs/constants.xs.inc", sub {
    my ($name, $value) = @_;

    # return false not to make a public constant
    return if $name =~ /^PRIVATE_CONST_/;

    return 1;
  });

  $converter->write_xs("Bar.xs");

=head1 CAVEAT EMPTOR

This is in its earliest stage, and APIs may be drastically changed.

=head1 DESCRIPTION

The ultimate goal of this module is to produce a decent set of XS interface files from a C header file. This is not meant to be a complete C header parser, nor a full-stacked authorizing tool for XS hackers. You'll always need to write/customize basic distribution information file (like C<cpanfile> or C<dist.ini> or traditional C<Makefile.PL>/C<Build.PL>), and, most importantly, C<typemap>.

C<Convert::H::XS> doesn't modify existing .xs files (with package declarations in it), nor create a whole skeleton of a distribution, by default.

=head1 METHODS

=head2 new
=head2 preprocess
=head2 process
=head2 write_all
=head2 write_xs
=head2 write_constants
=head2 write_enum_constants
=head2 write_functions

=head1 SEE ALSO

C<h2xs>, L<C::Scan>, L<Convert::Binary::C>

=head1 AUTHOR

Kenichi Ishigaki, E<lt>ishigaki@cpan.orgE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2013 by Kenichi Ishigaki.

This program is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

=cut
