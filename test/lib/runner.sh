#!/bin/sh

SCRIPT_DIR=`dirname "${BASH_SOURCE[0]}"`
SV2V="$SCRIPT_DIR/../../bin/sv2v"

assertExists() {
    file=$1
    [ -f "$file" ]
    assertTrue "$file does not exist" $?
}

# USAGE: simulate <vcd-file> <log-file> <top-module> <file> [<file> ...]
simulate() {
    # arguments
    sim_vcd="$1"; shift
    sim_log="$1"; shift
    sim_top="$1"; shift
    # compile the files
    sim_prog="$SHUNIT_TMPDIR/simprog.exe"
    iverilog \
        -o "$sim_prog" \
        -g2005 \
        -DTEST_VCD="\"$sim_vcd\"" \
        -DTEST_TOP=$sim_top \
        "$SCRIPT_DIR/tb_dumper.v" \
        "$@"
    assertTrue "iverilog on $1 failed" $?
    # run the simulation
    $sim_prog > $sim_log
    assertTrue "simulating $1 failed" $?
    # remove the date from the VCD
    sed -i.orig -e "1,3d" "$sim_vcd"
    # remove the "opened file..." prompt from the log
    sed -i.orig -e "1,1d" "$sim_log"
}

assertConverts() {
    ac_file="$1"
    ac_temp="$SHUNIT_TMPDIR/ac-conv-temp.v"
    $SV2V "$ac_file" 2> /dev/null > "$ac_temp"
    assertTrue "1st conversion of $ac_file failed" $?
    $SV2V "$ac_temp" 2> /dev/null > /dev/null
    assertTrue "2nd conversion of $ac_file failed" $?
}

simpleTest() {
    sv="$1"
    ve="$2"
    if [ -z ${NO_SEPARATE_TBS} ]; then
        tb="$3"
    else
        tb="$SCRIPT_DIR/empty.v"
    fi

    assertNotNull "SystemVerilog file not specified" $sv
    assertNotNull "Verilog file not specified" $ve
    assertNotNull "Testbench not specified" $tb

    assertExists $sv
    assertExists $ve
    assertExists $tb

    assertConverts "$sv"
    assertConverts "$ve"
    assertConverts "$tb"

    # convert the SystemVerilog source file
    cv="$SHUNIT_TMPDIR/conv.v"
    $SV2V $sv 2> /dev/null > $cv
    assertTrue "conversion failed" $?
    assertExists $cv

    ref_vcd="$SHUNIT_TMPDIR/ref.vcd"
    gen_vcd="$SHUNIT_TMPDIR/gen.vcd"
    ref_log="$SHUNIT_TMPDIR/ref.log"
    gen_log="$SHUNIT_TMPDIR/gen.log"

    # simulate and compare the two files
    simulate "$ref_vcd" "$ref_log" top "$ve" "$tb"
    simulate "$gen_vcd" "$gen_log" top "$cv" "$tb"
    diff "$ref_vcd" "$gen_vcd" > /dev/null
    assertTrue "VCDs are different" $?
    output=`diff "$ref_log" "$gen_log"`
    assertTrue "Simulation outputs differ:\n$output" $?
}

runTest() {
    test="$1"
    simpleTest "${test}.sv" "${test}.v" "${test}_tb.v"
}

suite() {
    for test in `ls *.sv | sed -e "s_\.sv\\\$__"`; do
        eval "test_$test() { runTest \"$test\"; }"
        suite_addTest "test_$test"
    done
}

. shunit2

