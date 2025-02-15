#!/usr/bin/env perl
use strict;
use POSIX;
use Getopt::Long;

my ($file_in,$file_out,$file_upd);
my ($verbose,$get_count,$get_count_match,$set_count,$set_count_match) = (0,0,0,0,0);
my @lines;
my @OPS;
my %PATW;
Getopt::Long::Configure ("bundling");
my $result = GetOptions (
        "v+"   => \$verbose,
        "i=s" => \$file_in,
        "o=s" => \$file_out,
        "u=s" => \$file_upd);

usage() if(!$result);
@OPS = @ARGV;
usage() if !@OPS;

if(defined $file_upd) {
    if(defined $file_out) {
        die "Cant write and update different files\n" if $file_upd ne $file_out;
    } else {
        $file_out = $file_upd;
    }
    if(defined $file_in) {
        die "Cant read and update different files\n" if $file_upd ne $file_in;
    } else {
        $file_in = $file_upd;
    }
}

if(defined $file_in) {
    die "open $file_in : $!\n" if !open(F,'<'.$file_in);
    @lines = map { chomp; $_ } <F>;
    close(F);
} else {
    @lines = map { chomp; $_ } <>;
}

my @path;
my $lc = 0;
my $nchg = 0;
foreach my $l (@lines) {
    $lc++;
    next if $l =~ /^\s*(#.*)?$/;
    #print "$lc: $l\n";
    if($l =~ /^(\s*)([a-z]([a-z0-9_-]*)?[a-z0-9])(\s*)=(\s*)(.*)$/i) {
        my ($sp1,$name,$sp2,$sp3,$val) = ($1,$2,$4,$5,$6);
        $sp1 = '' if !defined $sp1;
        $sp2 = '' if !defined $sp2;
        $sp3 = '' if !defined $sp3;
        my $orig_val = $val;
        my $prefix = join('.',@path);
        my $sp4 = '';
        if($val =~ /^(\S.*)$/) {
            my $fq = 0;
            ($val,$sp4,$fq) = parse_str_val($val);
            die "Bad value '$val'\n" if $sp4 ne '' && $sp4 !~ /\s*#.*$/;
            $prefix .= '.' if $prefix ne '';
            $prefix .= $name;
            my ($newval,$sp5) = changes("$prefix",\@OPS,$val);
            next if !defined $newval;
            if($newval ne $val || $sp4 ne $sp5) {
                $nchg++;
                $newval = must_q($newval,$fq);
                if($orig_val ne $newval.$sp5) {
                    if($verbose) {
                        if($verbose > 1) {
                            print STDERR "OLD: '${sp1}${name}${sp2}=${sp3}${orig_val}'\n";
                            print STDERR "NEW: '${sp1}${name}${sp2}=${sp3}${newval}${sp5}'\n";
                        } else {
                            print STDERR "OLD: ${name} = ${orig_val}\n";
                            print STDERR "NEW: ${name} = ${newval}${sp5}\n";
                        }
                    }
                    $lines[$lc-1] = "${sp1}${name}${sp2}=${sp3}${newval}${sp5}";
                    $nchg++;
                } else {
                    if($verbose) {
                        print STDERR "No changes: '${name} = ${orig_val}'\n";
                    }
                }
            }
            next;
        }
        die "Line $lc: bad value '$val'\n";
    }
    if($l =~ /^([^\{\}]+)\{(.*)$/) {
        my ($begin,$tail) = ($1,$2);
        if(defined $tail) {
            die "Line $lc: '$l' Not an empty line after '{'\n" if $tail !~ /^\s*(#.*)?$/;
        }
        if($begin =~ /^\s*(\S+)\s*$/) {
            my $key = $1;
            die "Line $lc: bad key '$key'\n" if $key  !~ /^[a-z]([a-z0-9_-]+)?[a-z0-9]$/i;
            push @path,$key;
            next;
        }
        die "Line $lc: '$l' Invalid syntax.\n";
    }
    if($l =~ /^([^\{\}]*)\}(.*)?$/) {
        my ($begin,$tail) = ($1,$2);
        if(defined $tail) {
            die "Line $lc: $l Not an empty line after '}'\n" if $tail !~ /^\s*(#.*)?$/;
        }
        die "Line $lc: '$l' Not an empty line before '}'\n" if $begin !~ /^\s*$/;
        die "Line $lc: '$l' Missmatch { }\n" if !@path;
        pop @path;
        next;
    }
    
    die "Line $lc: '$l' Invalid syntax.\n";
}
if($get_count + $set_count == 0) {
    print STDERR "Missing commans\n";
    exit(1);
}
if($get_count_match + $set_count_match == 0) {
    print STDERR "No matches\n" if $verbose;
    exit(1);
}

if($nchg) {
    if(defined $file_out) {
        if($file_out ne '-') {
            open(F,'>'.$file_out) || die "Write error: $!\n";
            print F join("\n",@lines),"\n";
            close(F);
            exit(0);
        }
        print join("\n",@lines),"\n";
        exit(0);
    }
    die "No file specified to save changes to.\n";
}
exit(0);

sub changes {
 my ($prefix,$ops,$val) = @_;
 my ($sp,$nc) = ('',0);

 my $i = 0;
 while($i <= $#{$ops}) {
    my $op = $ops->[$i++];
    my $mp = $ops->[$i++];
    if($op eq 'get' || $op eq 'getre' ) {
        $get_count++;
        if($op eq 'get' ? my_match_w($prefix,$mp) : my_match_re($prefix,$mp)) {
            print "$prefix = ",quote($val),"\n";
            $get_count_match++;
        }
        next;
    } elsif($op eq 'set' || $op eq 'setre') {
        $set_count++;
        my $nv = $ops->[$i++];
        if($op eq 'set' ? my_match_w($prefix,$mp) : my_match_re($prefix,$mp)) {
            my $fq = 0;
            ($val,$sp,$fq) = parse_str_val($nv);
            die "Bad value '$nv'\n" if $sp ne '' && $sp !~ /\s*#.*$/;
            $val = $fq ? quote($val) : $val;
            print STDERR "SET '$val' '$sp'\n" if $verbose > 2;
            $get_count_match++;
            $nc++;
        }
    }
 }
 return $nc ? ($val,$sp):(undef,undef);
}

sub glob2pat{
    my $globstr = shift;
    my %patmap = (
        '*' => '.*',
        '?' => '.',
        '[' => '[',
        ']' => ']',
    );
    $globstr =~ s{(.)} { $patmap{$1} || "\Q$1" }ge;
    return '^' . $globstr . '$';
}

sub my_match_re {
    my ($prefix,$mp) = @_;
    return $prefix eq $mp if $mp !~ /[\*\?\+\^\$]/;
    my $re = eval { qr/$mp/ };
    die "Bad re '$mp' : $@ \n" if $@;
    return $prefix =~ qr/$mp/ if !$@;
    return 0;
}

sub my_match_w {
    my ($prefix,$mp) = @_;
    return $prefix eq $mp if $mp !~ /[\*\?\+\[\]\^\$]/;
    my $mpw = $PATW{$mp};
    if(!defined $mpw) {
        $mpw = glob2pat($mp);
        print STDERR "Use wilcard $mpw for $mp\n" if $verbose > 1;
        $PATW{$mp} = $mpw;
    }
    my $re = eval { qr/$mpw/ };
    die "Bad re '$mpw' : $@ \n" if $@;
    return $prefix =~ qr/$mpw/ if !$@;
    return 0;
}

sub must_q {
    my ($val,$force) = @_;
    $val = $2 if $val =~ /^(["'])(.*)\1$/;
    return quote($val) if $val =~ /[\s"]/ || $force;
    return $val;
}

sub quote {
    my $val = shift;
    return $val if $val !~ /[\s"]/;
    $val =~ s/([^\\])"/\1\\"/g;
    return '"'.$val.'"';
}

sub parse_str_val {
    my $val = shift;
    die "bad val '$val'\n" if !defined $val || $val eq '';
    my ($rval,$sp,$fq,$qc) = ('','',0,undef);
    my @v = split //,$val;
    if($v[0] eq '"' || $v[0] eq "'") {
        $qc = $v[0]; $fq=1;
        shift @v;
    }
    while($#v >= 0) {
        my $c = shift @v;
        if($c ne '\\') {
            if($c eq ' ' || $c eq '\t') {
                if(!defined $qc) {
                    $sp = $c.join('',@v);
                    return ($rval,$sp,$fq);
                }
            }
            if(defined $qc && $c eq $qc) {
                $sp = join('',@v);
                return ($rval,$sp,$fq);
            }
            $rval .= $c;
            next;
        }
        my $c2 = shift @v;
        last if !defined $c2;
        $rval .= $c.$c2;
    }
    $sp = join('',@v);
    return ($rval,$sp,$fq);
}

sub usage {
        print "Usage:\n",
        " hocon [-v] [-i inputfile] [-o outputfile] [-u file] commands [ commands ... ]\n",
        "  -v         -- verbose/debug\n",
        "  -i file    -- read from file\n",
        "  -o file    -- write to file (overwrite existing file).\n",
        "  -u file    -- update file. Short form of '-i file -o file'\n",
        " Commands: \n",
        "     get[re] name\n",
        "     set[re] name val\n";
        exit 1;
}

# vim: set ts=4 sw=4 et:
