// Gen Thang menu overlay: a 32x28 character screen in a 2bpp shadowed font.
// A double-size chrome title, gradient text, a shaded selection bar and separator
// lines over a vertical gradient; kept small to fit beside the core.
//
// Layout (256x224 overlay pixels):
//   y   4- 19  title: character row 0, columns 0-15, double size
//   y  24-223  character rows 3-27 (row 3 subtitle, rows 24+ status/help)
//   y  36/37, 188/189  separator lines (rows 4 and 23 are left empty)
//
// PicoRV32 register (iosys 0x0200_0000), one write per command:
//   [25:24]=0: character [7:0] at column [20:16], row [12:8]
//   [25:24]=1/2: overlay on/off (decoded in iosys)
//   [25:24]=3: register [23:16] <= [15:0]; 0: selected row (31 = none)
module textdisp #(
    parameter FONT = "demofont.hex"     // 2bpp font from gen_demofont.py
) (
    input             clk,              // iosys clock (writes)
    input             hclk,             // HDMI pixel clock (rendering)
    input             resetn,

    input      [7:0]  x,                // 0-255, each held for 3-4 hclk cycles
    input      [7:0]  y,                // 0-223
    output reg [14:0] color,            // BGR5, 4 hclk cycles behind x

    input      [3:0]  reg_char_we,
    input      [31:0] reg_char_di
);

function [14:0] rgb(input [4:0] r, input [4:0] g, input [4:0] b);
    rgb = {b, g, r};
endfunction

// 80s chrome: sky gradient on the top half, sunset on the bottom half
function [14:0] chrome16(input [3:0] i);
    case (i)
    4'd0:  chrome16 = rgb( 4,  8, 20);  4'd1:  chrome16 = rgb( 6, 12, 24);
    4'd2:  chrome16 = rgb( 8, 17, 28);  4'd3:  chrome16 = rgb(12, 21, 31);
    4'd4:  chrome16 = rgb(17, 25, 31);  4'd5:  chrome16 = rgb(22, 28, 31);
    4'd6:  chrome16 = rgb(27, 30, 31);  4'd7:  chrome16 = rgb(31, 31, 31);
    4'd8:  chrome16 = rgb(12,  4, 10);  4'd9:  chrome16 = rgb(16,  6, 10);
    4'd10: chrome16 = rgb(21,  8,  8);  4'd11: chrome16 = rgb(26, 12,  6);
    4'd12: chrome16 = rgb(31, 16,  4);  4'd13: chrome16 = rgb(31, 21,  8);
    4'd14: chrome16 = rgb(31, 26, 14);  default: chrome16 = rgb(31, 30, 22);
    endcase
endfunction

function [14:0] list8(input [2:0] i);           // file list: ice to pink
    case (i)
    3'd0: list8 = rgb(18, 28, 31);  3'd1: list8 = rgb(22, 30, 31);
    3'd2: list8 = rgb(27, 31, 31);  3'd3: list8 = rgb(31, 31, 31);
    3'd4: list8 = rgb(31, 22, 29);  3'd5: list8 = rgb(31, 17, 27);
    3'd6: list8 = rgb(28, 12, 25);  default: list8 = rgb(24,  9, 22);
    endcase
endfunction

localparam [14:0] C_SHADOW = 15'b00110_00000_00001;
localparam [14:0] C_WHITE  = 15'h7FFF;

// ---- character memory and registers (iosys clock) --------------------------------
reg [7:0] cmem [0:1023];                // {row[4:0], col[4:0]}
wire       cwe = reg_char_we[0];
wire [1:0] cmd = reg_char_di[25:24];

always @(posedge clk)
    if (cwe && cmd == 2'd0)
        cmem[{reg_char_di[12:8], reg_char_di[20:16]}] <= reg_char_di[7:0];

reg [4:0] sel_row_w = 5'd31;
always @(posedge clk)
    if (cwe && cmd == 2'd3 && reg_char_di[23:16] == 8'd0)
        sel_row_w <= reg_char_di[4:0];

reg [15:0] fmem [0:1023];               // {char[6:0], row[2:0]}
initial $readmemh(FONT, fmem);

// ---- per-line state (hclk): y changes in hblank, so line-constant colours are
// registered here instead of being carried down the pixel pipeline
reg [4:0]  sel_row;                    // quasi-static, changes only between key presses
reg [7:0]  l_y;
reg        l_title, l_text, l_sub, l_status, l_sel, l_sep;
reg [14:0] l_body, l_bg;
localparam [14:0] BAR_HUE = 15'b11111_00000_11111;     // magenta

wire [7:0] tline = l_y - 8'd4;
wire [2:0] bar_sh = l_y[2] ? {1'b0, l_y[1:0]} : {1'b0, ~l_y[1:0]};

always @(posedge hclk) begin
    sel_row <= sel_row_w;

    l_y <= y;
    l_title <= y >= 8'd4 && y < 8'd20;
    l_text <= y[7:3] >= 5'd3;
    l_sub <= y[7:3] == 5'd3;
    l_status <= y[7:3] >= 5'd24;
    l_sel <= y[7:3] == sel_row && y[7:3] >= 5'd3;
    l_sep <= y == 8'd36 || y == 8'd37 || y == 8'd188 || y == 8'd189;

    if (l_title)       l_body <= chrome16(tline[3:0]);
    else if (l_sel)    l_body <= C_WHITE;
    else if (l_sub)    l_body <= rgb(31, 12, 26);
    else if (l_status) l_body <= rgb(31, 25, 6);
    else               l_body <= list8(l_y[2:0]);
    if (l_sep)         l_bg <= rgb(0, 24, 31);
    else if (l_sel)    l_bg <= {BAR_HUE[14:10] >> bar_sh, BAR_HUE[9:5] >> bar_sh, BAR_HUE[4:0] >> bar_sh};
    else               l_bg <= rgb({3'd0, ~l_y[7:6]}, 5'd0, 5'd2 + {2'd0, l_y[7:5]});
end

// ---- per-pixel pipeline: address, character, glyph row, compose -------------------
reg [9:0] b_addr;
reg [2:0] b_frow, b_fcol, c_frow, c_fcol, d_fcol;
reg [7:0] c_char;
reg [15:0] d_font;

always @(posedge hclk) begin
    b_addr <= l_title ? {6'd0, x[7:4]} : {l_y[7:3], x[7:3]};
    b_frow <= l_title ? tline[3:1] : l_y[2:0];
    b_fcol <= l_title ? x[3:1] : x[2:0];

    c_char <= cmem[b_addr];
    {c_frow, c_fcol} <= {b_frow, b_fcol};

    d_font <= fmem[{c_char[6:0], c_frow}];
    d_fcol <= c_fcol;
end

wire [1:0] pix = (l_title || l_text) ? d_font[{d_fcol, 1'b0} +: 2] : 2'd0;
always @(posedge hclk)
    case (pix)
    2'd0: color <= l_bg;
    2'd1: color <= C_SHADOW;
    2'd2: color <= l_body;
    2'd3: color <= l_sel ? rgb(31, 31, 12) : C_WHITE;
    endcase

endmodule
