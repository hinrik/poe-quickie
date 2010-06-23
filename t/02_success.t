use strict;
use warnings;
use POE;
use POE::Quickie;
use Test::More tests => 4;

POE::Session->create(
    package_states => [
        (__PACKAGE__) => [qw(
            _start
            stdout
            stderr
        )],
    ],
);

POE::Kernel->run;

sub _start {
    my $heap = $_[HEAP];

    $heap->{quickie} = POE::Quickie->new();
    $heap->{quickie}->run(
        Program     => sub { print "foo\n" },
        StdoutEvent => 'stdout',
        Context     => 'baz',
    );
}

sub stdout {
    my ($heap, $output, $id, $context) = @_[HEAP, ARG0..ARG2];
    is($output, 'foo', 'Got stdout');
    is($context, 'baz', 'Got context');
    my $programs = $heap->{quickie}->programs();
    is($programs->{$id}, 'baz', '$quickie->programs() works');
    
    $heap->{quickie}->run(
        Program     => sub { warn "bar\n" },
        StderrEvent => 'stderr',
    );
}

sub stderr {
    my ($heap, $error) = @_[HEAP, ARG0];
    is($error, 'bar', 'Got stderr');
    $heap->{quickie}->shutdown();
}
