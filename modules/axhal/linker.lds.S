OUTPUT_ARCH(%ARCH%)             # 指定目标架构

BASE_ADDRESS = %KERNEL_BASE%;   # 内核基地址

ENTRY(_start)                   # 入口点
SECTIONS
{
    . = BASE_ADDRESS;           # 即内核的基地址，后续段的地址会基于此自动增长。
    _skernel = .;               # 定义一个符号 _skernel，它表示内核的起始地址（即当前地址值）。

    # 代码段 .text
    .text : ALIGN(4K) {
        _stext = .;             # 代码段开始标记         
        *(.text.boot)           # 引导代码
        *(.text .text.*)        # 所有代码段 *: 表示匹配输入文件中所有 .text、.text.* 段。
        . = ALIGN(4K);          # 4K对齐
        _etext = .;             # 代码段结束标记
    }

    # 只读段 .rodata 段存储内核的只读数据，例如字符串常量和全局只读变量。
    .rodata : ALIGN(4K) {
        _srodata = .;           # 只读数据段开始
        *(.rodata .rodata.*)    # 只读数据
        *(.srodata .srodata.*)  # 小数据只读段
        *(.sdata2 .sdata2.*)    # 小数据段
        . = ALIGN(4K);          # 4K对齐
        _erodata = .;           # 只读数据段结束
    }
    # 数据段 .data 和 .tdata 
    # .data 段存储可修改的全局数据，包括内核的页表数据（.data.boot_page_table）。
    .data : ALIGN(4K) {
        _sdata = .;
        *(.data.boot_page_table)
        . = ALIGN(4K);
        *(.data .data.*)
        *(.sdata .sdata.*)
        *(.got .got.*)
    }

    # .tdata 段是线程局部存储（TLS）的初始化数据段，按 16 字节对齐。
    .tdata : ALIGN(0x10) {
        _stdata = .;
        *(.tdata .tdata.*)
        _etdata = .;
    }

    .tbss : ALIGN(0x10) {
        _stbss = .;
        *(.tbss .tbss.*)
        *(.tcommon)
        _etbss = .;
    }

    . = ALIGN(4K);
    _percpu_start = .;
    _percpu_end = _percpu_start + SIZEOF(.percpu);
    # .percpu 段存储每个 CPU 的私有数据。
    .percpu 0x0 : AT(_percpu_start) {
        _percpu_load_start = .;
        *(.percpu .percpu.*)
        _percpu_load_end = .;
        . = _percpu_load_start + ALIGN(64) * %SMP%; # ALIGN(64) * %SMP%: 按 64 字节对齐，每个 CPU 分配一段独立的区域。
    }
    . = _percpu_end;

    . = ALIGN(4K);
    _edata = .;

    # BSS 段
    .bss : ALIGN(4K) {
        # boot_stack 和 boot_stack_top: 定义启动栈的起始和结束地址。
        boot_stack = .;
        *(.bss.stack)
        . = ALIGN(4K);
        boot_stack_top = .;

        _sbss = .;
        *(.bss .bss.*)
        *(.sbss .sbss.*)
        *(COMMON)
        . = ALIGN(4K);
        _ebss = .;
    }

    _ekernel = .;

    # 将 .comment、.gnu、.note 和 .eh_frame 段丢弃（不包含在最终映像中），通常用于去除调试信息和无用的元数据。
	/DISCARD/ : {
        *(.comment) *(.gnu*) *(.note*) *(.eh_frame*)
    }
}

SECTIONS {
    linkme_IRQ : { *(linkme_IRQ) }
    linkm2_IRQ : { *(linkm2_IRQ) }
    linkme_PAGE_FAULT : { *(linkme_PAGE_FAULT) }
    linkm2_PAGE_FAULT : { *(linkm2_PAGE_FAULT) }
}
INSERT AFTER .tbss;
