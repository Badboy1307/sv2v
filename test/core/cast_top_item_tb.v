module top;
    genvar i;
    generate
        for (i = 0; i < 32; i = i + 1)
            mod #(i) m();
    endgenerate
endmodule
