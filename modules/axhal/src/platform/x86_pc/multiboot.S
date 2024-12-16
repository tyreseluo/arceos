# Bootstrapping from 32-bit with the Multiboot specification.
# See https://www.gnu.org/software/grub/manual/multiboot/multiboot.html

.section .text.boot
.code32
.global _start
_start:
    mov     edi, eax        # arg1: magic: 0x2BADB002 传递 magic number 到 edi
    mov     esi, ebx        # arg2: multiboot info 传递 multiboot 信息到 esi
    jmp     bsp_entry32     # 跳转到 32 位入口

.balign 4
.type multiboot_header, STT_OBJECT
multiboot_header:
    .int    {mb_hdr_magic}                      # magic: 0x1BADB002
    .int    {mb_hdr_flags}                      # flags
    .int    -({mb_hdr_magic} + {mb_hdr_flags})  # checksum
    .int    multiboot_header - {offset}         # header_addr
    .int    _skernel - {offset}                 # load_addr
    .int    _edata - {offset}                   # load_end
    .int    _ebss - {offset}                    # bss_end_addr
    .int    _start - {offset}                   # entry_addr

@ multiboot_header:
@     .int {mb_hdr_magic}                      # Multiboot 魔数
@     .int {mb_hdr_flags}                      # 标志位
@     .int -({mb_hdr_magic} + {mb_hdr_flags})  # 校验和
@     .int multiboot_header - {offset}         # 头部地址
@     .int _skernel - {offset}                 # 内核加载地址
@     .int _edata - {offset}                   # 数据段结束地址
@     .int _ebss - {offset}                    # BSS 段结束地址
@     .int _start - {offset}                   # 内核入口地址

# Common code in 32-bit, prepare states to enter 64-bit.
.macro ENTRY32_COMMON
    # set data segment selectors
    mov     ax, 0x18  # 段选择子，指向 GDT 的数据段 0x18 是 GDT 中数据段的偏移。这是必须的，因为所有的内存访问都需要依赖段寄存器。
    mov     ss, ax    # 设置栈段
    mov     ds, ax    # 设置数据段
    mov     es, ax    # 设置附加数据段
    mov     fs, ax    # 设置 fs 寄存器
    mov     gs, ax    # 设置 gs 寄存器

    # set PAE, PGE bit in CR4
    mov     eax, {cr4}
    mov     cr4, eax

    # load the temporary page table
    lea     eax, [.Ltmp_pml4 - {offset}]
    mov     cr3, eax

    # set LME, NXE bit in IA32_EFER
    mov     ecx, {efer_msr}
    mov     edx, 0
    mov     eax, {efer}
    wrmsr

    # set protected mode, write protect, paging bit in CR0
    mov     eax, {cr0}
    mov     cr0, eax
.endm

# Common code in 64-bit
.macro ENTRY64_COMMON
    # clear segment selectors
    xor     ax, ax  # 将 ax 清零
    mov     ss, ax  # 设置栈段为空
    mov     ds, ax  # 设置数据段为空
    mov     es, ax  # 清空附加段
    mov     fs, ax  # 清空 fs 寄存器
    mov     gs, ax  # 清空 gs 寄存器
.endm

.code32
bsp_entry32:
    lgdt    [.Ltmp_gdt_desc - {offset}]             # load the temporary GDT lgdt [.Ltmp_gdt_desc - {offset}]  # 加载 GDT 描述符
    ENTRY32_COMMON
    ljmp    0x10, offset bsp_entry64 - {offset}    # 0x10 is code64 segment  0x10 是 64 位代码段的选择子。跳转到 bsp_entry64 开始 64 位模式的初始化。

.code32
.global ap_entry32
ap_entry32:
    ENTRY32_COMMON
    ljmp    0x10, offset ap_entry64 - {offset}     # 0x10 is code64 segment

.code64
bsp_entry64:
    ENTRY64_COMMON

    # set RSP to boot stack
    movabs  rsp, offset {boot_stack}    # 设置栈基址
    add     rsp, {boot_stack_size}      # 将栈指针设置到栈顶

    # boot_stack 是栈的起始地址。
    # boot_stack_size

    # call rust_entry(magic, mbi)
    movabs  rax, offset {entry}  # Rust 内核的入口地址
    call    rax                  # 跳转到入口函数
    jmp     .Lhlt

.code64
ap_entry64:
    ENTRY64_COMMON

    # set RSP to high address (already set in ap_start.S)
    mov     rax, {offset}
    add     rsp, rax

    # call rust_entry_secondary(magic)
    mov     rdi, {mb_magic}
    movabs  rax, offset {entry_secondary}
    call    rax
    jmp     .Lhlt

.Lhlt:
    hlt
    jmp     .Lhlt

.section .rodata
.balign 8
.Ltmp_gdt_desc:
    .short  .Ltmp_gdt_end - .Ltmp_gdt - 1   # limit
    .long   .Ltmp_gdt - {offset}            # base

.section .data
.balign 16
.Ltmp_gdt:
    .quad 0x0000000000000000    # 0x00: null
    .quad 0x00cf9b000000ffff    # 0x08: code segment (base=0, limit=0xfffff, type=32bit code exec/read, DPL=0, 4k)
    .quad 0x00af9b000000ffff    # 0x10: code segment (base=0, limit=0xfffff, type=64bit code exec/read, DPL=0, 4k)
    .quad 0x00cf93000000ffff    # 0x18: data segment (base=0, limit=0xfffff, type=32bit data read/write, DPL=0, 4k)
.Ltmp_gdt_end:

.balign 4096
.Ltmp_pml4:
    # 0x0000_0000 ~ 0xffff_ffff
    .quad .Ltmp_pdpt_low - {offset} + 0x3   # PRESENT | WRITABLE | paddr(tmp_pdpt)
    .zero 8 * 510
    # 0xffff_ff80_0000_0000 ~ 0xffff_ff80_ffff_ffff
    .quad .Ltmp_pdpt_high - {offset} + 0x3  # PRESENT | WRITABLE | paddr(tmp_pdpt)

# FIXME: may not work on macOS using hvf as the CPU does not support 1GB page (pdpe1gb)
.Ltmp_pdpt_low:
    .quad 0x0000 | 0x83         # PRESENT | WRITABLE | HUGE_PAGE | paddr(0x0)
    .quad 0x40000000 | 0x83     # PRESENT | WRITABLE | HUGE_PAGE | paddr(0x4000_0000)
    .quad 0x80000000 | 0x83     # PRESENT | WRITABLE | HUGE_PAGE | paddr(0x8000_0000)
    .quad 0xc0000000 | 0x83     # PRESENT | WRITABLE | HUGE_PAGE | paddr(0xc000_0000)
    .zero 8 * 508

.Ltmp_pdpt_high:
    .quad 0x0000 | 0x83         # PRESENT | WRITABLE | HUGE_PAGE | paddr(0x0)
    .quad 0x40000000 | 0x83     # PRESENT | WRITABLE | HUGE_PAGE | paddr(0x4000_0000)
    .quad 0x80000000 | 0x83     # PRESENT | WRITABLE | HUGE_PAGE | paddr(0x8000_0000)
    .quad 0xc0000000 | 0x83     # PRESENT | WRITABLE | HUGE_PAGE | paddr(0xc000_0000)
    .zero 8 * 508
