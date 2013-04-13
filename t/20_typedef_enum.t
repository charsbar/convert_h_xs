use strict;
use warnings;
use Test::More;
use Test::Differences;
use Convert::H::XS;
use File::Temp;

{
  my $dir = File::Temp->newdir;
  my $file = "$dir/foo.h";
  {
    open my $fh, ">", $file;
    print $fh <<"END";
typedef enum {
  FOO = 0,
  BAR,
  BAZ
} rc;
END
  }

  if (-f $file) {
    my $converter = Convert::H::XS->new;
    $converter->process($file);

    eq_or_diff $converter->{stash}{typedef_enum} => {
      rc => [
        ['FOO', '0'], # XXX
        ['BAR', 1],
        ['BAZ', 2],
      ],
    }, 'got correct typedef enum info';
  }
}


done_testing;
