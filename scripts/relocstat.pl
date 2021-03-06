#!/usr/bin/env perl

#
# Use example: cd /opt/OOInstall/program
#              preloc --quiet --plt --for=svx *.so | sort | c++filt > svx
#
# use --strip to get the symbols for the constructors with the method name 
#	stripped
#


# misc. argument options / defaults
my $opt_plt_too = 0;
my $random_symbol_sample = 0;
my $do_data_profile = 0;
my $summary_only = 0;
my $global_warned_symbols = 0;

sub read_sections($$)
{
    my $file = shift;
    my $lib = shift;
    my $pipe;
    my %sections;

    $lib->{sections} = \%sections;

    open ($pipe, "readelf -W -e $file |") || die "Can't readelf -W -e $file: $!";
    while (<$pipe>) {
	m/\s*\[\s*([0-9]*)\]\s+([\S\._]*)\s+([A-Za-z]*)\s+([0-9a-f]*)\s+([0-9a-f]*)\s+([0-9a-f]*)\s+/ || next;
	my ($section, $type, $address, $offset, $size) = ($2, $3, $4, $5, $6);
	$section && $type || next;
	$size = hex ($size);

#	print "Section $section size $size\n";
	$lib->{sections}->{$section} = $size;
    }
    close ($pipe);
}

sub read_relocs($$)
{
    my $file = shift;
    my $lib = shift;
    my $pipe;
    my %relocs;
    my %symbols;
    my %used;
    my $in_plt = 0;

#    print "Read '$file'\n";

    open ($pipe, "readelf -r -W $file |") || die "Can't readelf -r $file: $!";
    while (<$pipe>) {
	if (m/'.rel.plt'/) {
	    $in_plt = 1;
	    next;
	}
	if (! m/^([0-9a-f]+)\s+([0-9a-f]+)\s+(R_\S+)\s+([0-9a-f]+)\s+(.*)\s*/) {
#	    print "Bin line '$_'\n";
            next;
	}
	my ($offset, $info, $type, $loc, $sym) = ($1, $2, $3, $4, $5);
#	print "$sym reloc at 0x$offset : $type, $loc, $sym\n";
	if ($in_plt) {
	    $lib->{used_in_plt}->{$sym} = 1;
	} else {
	    my $lst; 
	    if (!defined ($symbols{$sym})) {
		my @rlst;
		$lst = \@rlst;
	    } else {
		$lst = $symbols{$sym};
	    }
	    push @{$lst}, hex ($offset);
	    $symbols{$sym} = $lst;
	}
    }
    close ($pipe);

    $lib->{file} = $file;
    $lib->{relocs} = \%symbols;
    $lib->{used} = \%used;
}

sub has_symbols($)
{
    my $filename = shift;
    my $FILE;
    open ($FILE, "file -L $filename |");
    my $fileoutput = <$FILE>;
    close ($FILE);
    if (( $fileoutput =~ /not stripped/i ) && ( $fileoutput =~ /\bELF\b/ )) { $symbols = 1; }
    else { $symbols = 0; }
    return $symbols;
}

sub read_symbols($$)
{
    my $file = shift;
    my $lib = shift;
    my $pipe;
    my %def;
    my %undef;
    my %data;
    my %addr_space;

#    print "Read '$file'\n";

    my $dumpsw = '-t';
    if (!has_symbols ($file)) {
	if (!$global_warned_symbols) {
	    print "relocstat does better with symbols\n";
	    $global_warned_symbols = 1;
	}
	$dumpsw = '-T';
    }

    open ($pipe, "objdump $dumpsw $file |") || die "Can't objdump $dumpsw $file: $!";
    while (<$pipe>) {
	/([0-9a-f]*)\s+([gw ])\s+..\s+(\S*)\s*([0-9a-f]+)..............(.*)/; # || next;

	my ($address, $linkage, $type, $size, $symbol) = ($1, $2, $3, $4, $5);
#	print "Symbol '$symbol' type '$type' '$linkage' addr $address, size $size\n";

	if (!$symbol || !$type) {
#	    print "Bogus line: $_\n";
	    next;
	}

	if ($type eq '.data') {
	    my $realsize = hex ($size);
	    my $realaddress = hex ($address);
	    my %datum;
	    $datum{size} = $realsize;
	    $datum{address} = $realaddress;
	    $datum{symbol} = $symbol;
	    $data{$symbol} = \%datum;
#	    print "Symbol '$symbol' type '$type' '$linkage' addr 0x$address, size $size\n";

	    # yes there should be a btree in perl.
	    for (my $i = 0; $i < $realsize; $i+=4) {
		my $key = $realaddress + $i;
#		printf "Set... '$key'\n";
#		defined $addr_space{$key} && die "Overlap: $key";
		$addr_space{$key} = \%datum;
	    }
	}

	if ($type ne '*UND*') {
	    $def{$symbol} = $linkage;
	} else {
	    $undef{$symbol} = $linkage;
	}
    }
    close ($pipe);

    $lib->{def} = \%def;
    $lib->{undef} = \%undef;
    $lib->{data} = \%data;
    $lib->{addr_space} = \%addr_space;
}

sub get_class_stem($)
{
    my $sym = shift;
    # relies on the integer in _ZTV[N]3...?? to disambiguate
    # class SetFoo vs. class SetFooExtra
    $sym =~ s/^_ZTVN*//;
    $sym =~ s/E*$//;
    return $sym;
}

sub breakdown_vtable($$$$)
{
    my $vtable_breakdown = shift;
    my $lib = shift;
    my $datum = shift;
    my $sym = shift;

    $sym =~ /_ZTI/ && return; # don't count type-info relocs

    my $constr = $datum->{symbol};
    
    my $cdata = $vtable_breakdown->{$constr};
    if (!defined $cdata) {
	my %some_cdata;
	$cdata = \%some_cdata;
	$vtable_breakdown->{$constr} = $cdata;

	$cdata->{slot_count} = 0;
	$cdata->{self_impl_slot_count} = 0;
	$cdata->{extern_impl_slot_count} = 0;
	$cdata->{stem} = get_class_stem ($constr);
	$cdata->{external_self} = 0;
    }

    $cdata->{slot_count}++;
    
    if ($sym =~ m/$cdata->{stem}/) {
	# internal symbol
	$cdata->{self_impl_slot_count}++;
	
	if (defined $lib->{undef}->{$sym}) {
	    $cdata->{external_self}++; # very unusual ...
	}
    }

    if (defined $lib->{undef}->{$sym}) {
	# external symbol
	$cdata->{extern_impl_slot_count}++;
    }
}

sub by_internal
{
  keys (%{$a->{relocs}}) <=> keys (%{$b->{relocs}});
}

sub is_vtable($)
{
    my $sym = shift;
    return $sym =~ /^_ZTV/;
}

sub is_rtti($)
{
    my $sym = shift;
    return $sym =~ /^_ZTI/ || $sym =~ /^_ZTS/;
}

sub find_nearest($$)
{
    my $addr_space = shift;
    my $addr = shift;
    for (my $delta = 0; $delta < (256 * 8); $delta += 4) {
	return ($addr_space->{$addr+$delta})->{symbol} if (defined $addr_space->{$addr + $delta});
	return ($addr_space->{$addr-$delta})->{symbol} if (defined $addr_space->{$addr - $delta});
    }
    return '<unknown>';
}

#
# munge options
#
my @files = ();
for my $arg (@ARGV) {
    if ($arg =~ m/^--data-profile/) {
	$do_data_profile = 1;
    } elsif ($arg =~ m/^--random-syms/) {
	$random_symbol_sample = 1;
    } elsif ($arg =~ m/^--summary/) {
	$summary_only = 1;
    } else {
	my ($dev,$ino,$mode,$nlink,$uid,$gid,$rdev,$size,
	    $atime,$mtime,$ctime,$blksize,$blocks)
	    = stat($arg);
	# ignore malingering empty libs created by mergelibs
	push @files, $arg if ($size != 0);
    }
}

#
# read relocation data from elf shared libraries
#
my @libs = ();
my $lib;
print STDERR "reading relocs ";
for my $file (@files) {
    my %lib_hash;
    my $lib = \%lib_hash;
    read_sections ($file, $lib);
    read_relocs ($file, $lib);
    read_symbols($file, $lib);
    push @libs, $lib;
    print STDERR ".";
}
print STDERR "\n";

my $do_print_relocs = 1;
my $do_print_data_breakdown = 1;
my $do_print_vtable_breakdown = 1;
my $do_section_breakdown = 1;
my $do_count_sym_sizes = 1;
my $do_method_relocs = 1;

my %data_breakdown;

if ($do_data_profile) {
    $do_print_relocs = 0;
    $do_print_data_breakdown = 0;
    $do_print_vtable_breakdown = 0;
    $do_method_relocs = 0;
    $data_breakdown{vtable} = 0;
    $data_breakdown{vtable_count} = 0;
    $data_breakdown{rtti_count} = 0;
    $data_breakdown{other} = 0;
}

my %section_breakdown;
my $total_section_size = 0;

my $total_symbol_entry_count = 0;
my $total_symbol_def_size = 0;
my $total_symbol_undef_size = 0;

my $total_method_reloc_count = 0;
my $total_method_reloc_size = 0;

#
# pretty print it
#
for $lib (sort by_internal @libs) {

# Overall relocation information
    if ($do_print_relocs)
    {   
	my $internal_weak_relocs = 0;
	my $internal_weak_thnk = 0;
	my $internal_strong_relocs = 0;
	my $external_relocs = 0;
	my $def = $lib->{def};
	my $undef = $lib->{undef};
	for $sym (keys %{$lib->{relocs}}) {
	    if (defined $undef->{$sym}) {
		$external_relocs++;
	    } elsif (defined $def->{$sym}) {
		if ($def->{$sym} =~ m/w/) {
		    $internal_weak_relocs++;
		    $internal_weak_thnk++ if ($sym =~ m/^_ZThn/);
		} else {
		    $internal_strong_relocs++;
		}
	    } else {
		print STDERR "broken symbol '$sym'\n";
	    }
	}
	my $total = keys %{$lib->{relocs}};
	my $percentage = sprintf ("%2.2g", $internal_strong_relocs / ($total + 1) * 100);

	if (!$summary_only) {
	    print $lib->{file} . " total relocs $total external $external_relocs, internal weak " .
		"$internal_weak_relocs (of which thnks $internal_weak_thnk), " .
		"internal strong $internal_strong_relocs: saving $percentage\%\n";
	}
    }

    if ($do_method_relocs) {
	$lib->{total_method_reloc_count} = 0;
	$lib->{total_method_reloc_size} = 0;
	for my $sym (keys %{$lib->{relocs}}) {
	    $sym =~ /^_ZN/ || $sym =~ /^_ZThn/ || next;

	    my $count = @{$lib->{relocs}->{$sym}};
	    my $size = 16 * $count; # .rel.dyn
	    $size += length ($sym) + 1 + 4; # \0, .hash etc.

#	    print "Reloc $sym: count $count size $size\n";
	    $total_method_reloc_count += $count;
	    $total_method_reloc_size += $size;
	    $lib->{total_method_reloc_count} += $count;
	    $lib->{total_method_reloc_size} += $size;
	}
    }

    if ($random_symbol_sample) {
	print "\n";

	my @keys = keys %{$lib->{relocs}};
	print "Random symbols:\n";
	for ($i = 0; $i < 20; $i++) {
	    my $sym = $keys[rand @keys];
	    my $demangled = `c++filt $sym`;
	    chomp $demangled;
	    print "$demangled\t$sym\n";
	}
    }

# Break down the .data section by object details:
    {
	my $vtable_size = 0;
	my $vtable_count = 0;
	my $rtti_size = 0;
	my $rtti_count = 0;
	my $other_size = 0;
	my $other_count = 0;
	for $sym (keys %{$lib->{data}}) {
	    my $data = ($lib->{data})->{$sym};
	    
	    if (is_vtable ($sym)) {
		$vtable_count++;
		$vtable_size += $data->{size};
		
	    } elsif (is_rtti ($sym)) {
		$rtti_count++;
		$rtti_size += $data->{size};
		
	    } else {
		$other_count++;
		$other_size += $data->{size};
	    }
	}
	my $total_size = 1.0 * ($vtable_size + $rtti_size + $other_size) / 100.0;

	if ($do_data_profile) {
	    $data_breakdown{vtable} += $vtable_size;
	    $data_breakdown{vtable_count} += $vtable_count;
	    $data_breakdown{rtti} += $rtti_size;
	    $data_breakdown{rtti_count} += $rtti_count;
	    $data_breakdown{other} += $other_size;
	    $data_breakdown{other_count} += $other_count;
	}

	if ($do_print_data_breakdown && $total_size && !$summary_only) {
	    print ".data:\n";
	    print " vtables: $vtable_count size $vtable_size bytes - " . sprintf ("%2.2g", $vtable_size/$total_size) . "\%\n";
	    print " rtti: $rtti_count size $rtti_size bytes - " . sprintf ("%2.2g", $rtti_size/$total_size) . "\%\n";
	    print " other: $other_count size $other_size bytes - " . sprintf ("%2.2g", $other_size/$total_size) . "\%\n";
	    print "\n";
	}
    }

    if ($do_print_vtable_breakdown)
    {
	my $vtable_relocs = 0;
	my $rtti_relocs = 0;
	my $data_relocs = 0;
	my $other_relocs = 0;
	my $addr_space = $lib->{addr_space};
	my $key_count = keys %{$lib->{addr_space}};
	my %vtable_breakdown;
	my %vtable_wasted;

	for $sym (keys %{$lib->{relocs}}) {
	    my $lst = ($lib->{relocs})->{$sym};
	    for $addr (@{$lst}) {
		if (defined $addr_space->{$addr}) {
		    my $datum = $addr_space->{$addr};

#		print "Hit '$sym' at " . sprintf ("0x%.8x", $addr) . "\n";
		    
		    if (is_vtable ($datum->{symbol})) {
			$vtable_relocs++;
			breakdown_vtable (\%vtable_breakdown, $lib, $datum, $sym);
			if (!defined $vtable_wasted{$sym} &&
			     defined $lib->{undef}->{$sym}) {
			    if (defined $lib->{used_in_plt}->{$sym}) {
#				print "Symbol '$sym' used in plt and in vtable\n";
			    } else {
#				print "Symbol '$sym' used in plt and in vtable\n";
				$vtable_wasted{$sym}++;
			    }
			}
		    } elsif (is_rtti ($datum->{symbol})) {
			$rtti_relocs++;
		    } else {
			$data_relocs++;
		    }
		} else {
		    $other_relocs++;
# relocs in the data section, but not inside one of our symbols.
#	    print "Odd '$sym' at " . sprintf ("0x%.8x", $addr) .
#		  " nearest '" . find_nearest ($addr_space, $addr) . "'\n";
		}
	    }
	}
	if (!$summary_only) {
	    print "Data section contains " . $key_count * 4 . " bytes\n";
	    my $total_relocs = 1.0 * ($vtable_relocs + $rtti_relocs + $data_relocs + $other_relocs) / 100.0;
	    print "reloc breakdown:\n";
	    if ($total_relocs > 0) {
		print " vtables: $vtable_relocs - " . sprintf ("%2.2g", $vtable_relocs/$total_relocs) . "\%\n";
		print " rtti: $rtti_relocs - " . sprintf ("%2.2g", $rtti_relocs/$total_relocs) . "\%\n";
		print " .data/non-vtable $data_relocs - " . sprintf ("%2.2g", $data_relocs/$total_relocs) . "\%\n";
		print " other: $other_relocs - " . sprintf ("%2.2g", $other_relocs/$total_relocs) . "\%\n";
		print " grand-total: " . ($vtable_relocs + $rtti_relocs + $data_relocs + $other_relocs) . "\n";
		print "\n";
	    } else {
		print " no relocs at all\n";
	    }
	}

	my $vtable_slot_count = 0;
	my $vtable_class_count = 0;
	my $vtable_self_impl_slot_count = 0;
	my $vtable_extern_impl_slot_count = 0;
	my $vtable_extern_self = 0;
	for my $vtbl (keys %vtable_breakdown) {
	    $vtable_class_count++;
	    $vtable_slot_count += $vtable_breakdown{$vtbl}->{slot_count};
	    $vtable_self_impl_slot_count += $vtable_breakdown{$vtbl}->{self_impl_slot_count};
	    $vtable_extern_impl_slot_count += $vtable_breakdown{$vtbl}->{extern_impl_slot_count};
	    $vtable_extern_self += $vtable_breakdown{$vtbl}->{external_self};
#	    print "Class '$vtbl': slots " . $vtable_breakdown{$vtbl}->{slot_count}
#		. " self-impl " . $vtable_breakdown{$vtbl}->{self_impl_slot_count} . "\n";
	}
	if ($vtable_class_count && !$summary_only) {
	    print "vtables breakdown\n";
	
	    print " vtables: $vtable_class_count\n";
	    print " slots / vtable: " . sprintf ("%.3g", $vtable_slot_count/$vtable_class_count) . " slots\n";
	    print " self-impl / vtable: " . sprintf ("%.3g", $vtable_self_impl_slot_count/$vtable_class_count) . " slots\n";
	    print " parent-impl / vtable: " . sprintf ("%.3g", ($vtable_slot_count - $vtable_self_impl_slot_count)/$vtable_class_count) . " slots\n";
	    print " *extern-impl / vtable: " . sprintf ("%.3g", $vtable_extern_impl_slot_count/$vtable_class_count) . " slots\n";
	    print " *extern-impl of self total: " . sprintf ("%.3g", $vtable_extern_self) . " slots\n";
	}

	if ($vtable_extern_impl_slot_count && !$summary_only) { # vtable wasted count
	    my $vtable_wasted_syms = 0;
	    my $vtable_wasted_size = 0;
	    for my $sym (keys %vtable_wasted) {
		$vtable_wasted_syms++;
		$vtable_wasted_size += length ($sym) + 1 + 4; # \0, .hash etc.
	    }
	    print " extern (only) vtable symbols:\n";
	    print "  wasted symbols: $vtable_wasted_syms (" .
		sprintf ("%.3g", ($vtable_wasted_syms * 100.0) / $vtable_extern_impl_slot_count) . "%)\n";
	    print "  wasted bytes: $vtable_wasted_size\n";
	}

	my %by_stem = (
		       '^_ZThn' => 'thunks',
		       '^_ZN' => 'methods',
		       '^_ZTI' => 'type info',
		       '^_ZTS' => 'type strings',
		       '^_ZTV' => 'vtables',
		       '^[^_]' => 'non-c++'
		       );
	my %syms_by_stem = ();
	for my $stem (keys %by_stem) {
	    $syms_by_stem{$stem} = 0;
	}
	for $sym (keys %{$lib->{relocs}}) {
	    for my $stem (keys %by_stem) {
		if ($sym =~ m/$stem/) {
		    $syms_by_stem{$stem}++;
		    last;
		}
	    }
	}
	print "Unique relocation breakdown by suffix:\n";
	for $stem (sort { $syms_by_stem{$b} <=> $syms_by_stem{$a} } (keys %by_stem)) {
	    print "  " . sprintf ("%6d", $syms_by_stem{$stem}) .
		" - " . $by_stem{$stem} . "\n";
	}
    }
    if ($do_section_breakdown) {
# cf. http://refspecs.freestandards.org/LSB_3.0.0/LSB-Core-generic/LSB-Core-generic/specialsections.html
	my %sections = (
	    '\.hash' => 'linking',
	    '\.dynsym' => 'linking',
	    '\.dynstr' => 'linking',
	    '\.rel\.plt' => 'linking',
	    '\.suse\.vtrelocs' => 'linking',
	    '\.plt' => 'linking',
	    '\.got' => 'linking',
	    '\.got\.plt' => 'linking',
	    '\.rel\.dyn' => 'data relocs',
	    '\.gnu\.version.*' => 'versioning',
	    '\.gcc_except_table' => 'exceptions',
	    '\.eh_frame.*' => 'exceptions',
	    '\.[cd]tors' => 'c/d-tors',
	    '\.data.*' => 'data',
	    '\.rodata' => 'data',
	    '\.bss' => 'bss',
#	    '\.rodata' => 'ro data'
#	    '\.bss' => 'scratch globals',
	    '\.debug.*' => 'debug',
	    '\.stab.*' => 'debug',
	    '\.comment' => 'comment',
	    '\.text' => 'code',
	    '\.init.*' => 'init/fini',
	    '\.fini.*' => 'init/fini',
	    '\.strtab' => 'symbols',
	    '\.symtab' => 'symbols'
	);
	for my $sect (keys %{$lib->{sections}}) {
	    my $bsect = 'misc';
	    for my $match (keys %sections) {
		if ($sect =~ m/^$match$/) {
		    $bsect = $sections{$match};
		    last;
		}
	    }
# 	    if ($bsect eq 'misc') {
#		print "Section $sect size " . $lib->{sections}->{$sect} . " is misc...\n";
#	    }
	    $section_breakdown{$bsect} = 0 if (!defined $section_breakdown{$bsect});
	    my $size = $lib->{sections}->{$sect};
	    $section_breakdown{$bsect} += $size;
	    $total_section_size += $size;
	}
    }
    if ($do_count_sym_sizes) {
	for $sym (keys %{$lib->{def}}) {
	    $total_symbol_entry_count++;
	    $total_symbol_def_size += length ($sym) + 1;
	}
	for $sym (keys %{$lib->{undef}}) {
	    $total_symbol_entry_count++;
	    $total_symbol_undef_size += length ($sym) + 1;
	}
    }
}

if (@libs > 1) {
    print "\n";
    print "--- Total summary ---\n";
    print "\n";
}

if ($do_data_profile) {
    print ".data summary:\n";
    print " vtables: " . $data_breakdown{vtable_count} . " size " . $data_breakdown{vtable} . " bytes\n";
    print " rtti: " . $data_breakdown{rtti_count} . " size " . $data_breakdown{rtti} . " bytes\n";
    print " other: " . $data_breakdown{other_count} . " size " . $data_breakdown{other} . " bytes\n";
    print "\n";
}

if ($do_section_breakdown) {
    print "Section size breakdown\n";

    if ($total_section_size)
    {
	for my $bsect (sort { $section_breakdown{$b} <=> $section_breakdown{$a} } (keys %section_breakdown)) {
	    next if ($section_breakdown{$bsect} < 1024);
	    print " " . sprintf ("%-15s", $bsect) .
		" " . sprintf ("%4d", ($section_breakdown{$bsect}/1024)) . 
		"kb - " . sprintf ("%2.2g", $section_breakdown{$bsect} * 100.0 /$total_section_size) . "\%\n";
	}
    }
    print " Total: $total_section_size bytes\n";
}

if ($do_count_sym_sizes) {
    print "Symbol entry counts:\n";
    print " ~total .dynsym entries: $total_symbol_entry_count\n";
    print " .dynstr size:\n";
    print "    def:    $total_symbol_def_size\n";
    print "    undef:  $total_symbol_undef_size\n";
    print "    (avg len): " . sprintf ("%3.2g\n", ($total_symbol_def_size + $total_symbol_undef_size) / ($total_symbol_entry_count + 1));
}

if ($do_method_relocs) {
    print "name\trelocs\tsize\n";
    for $lib (sort by_internal @libs) {
	
	print $lib->{file} . "\t" . 
	      $lib->{total_method_reloc_count} . "\t" .
	      $lib->{total_method_reloc_size} . "\n";
    }

    print "Totals:\n";
    print "  method relocs: $total_method_reloc_count\n";
    print "  size (bytes):  $total_method_reloc_size\n";
}

