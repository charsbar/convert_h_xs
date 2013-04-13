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
typedef struct _obj obj;
typedef struct {
  const char *name;
  unsigned int name_size;
} expr;
END
  }

  if (-f $file) {
    my $converter = Convert::H::XS->new;
    $converter->process($file);

    eq_or_diff $converter->{stash}{typedef_struct} => {
      obj => '_obj',
      expr => [
        'const char *name',
        'unsigned int name_size',
      ],
    }, 'got correct typedef struct info';
  }
}


done_testing;
