use std::ptr;

#[repr(C)]
pub struct BitStreamRust {
    pub number_of_bits_used: u32,
    pub number_of_bits_allocated: u32,
    pub read_offset: u32,
    pub data: *mut u8,
    pub copy_data: bool,
    pub stack_data: [u8; 256],
}

#[no_mangle]
pub unsafe extern "C" fn rust_bitstream_construct(bs: *mut BitStreamRust) {
    let bs = &mut *bs;
    bs.number_of_bits_used = 0;
    bs.number_of_bits_allocated = 256 * 8; // stackData size in bits
    bs.read_offset = 0;
    bs.data = bs.stack_data.as_mut_ptr();
    bs.copy_data = true;
    bs.stack_data.fill(0);
}

#[no_mangle]
pub unsafe extern "C" fn rust_bitstream_construct_data(
    bs: *mut BitStreamRust,
    data: *mut u8,
    length: u32,
    copy_data: bool,
) {
    let bs = &mut *bs;
    bs.number_of_bits_used = length * 8;
    bs.read_offset = 0;
    bs.copy_data = copy_data;
    if copy_data {
        let size = length as usize;
        bs.number_of_bits_allocated = length * 8;
        if size <= 256 {
            bs.data = bs.stack_data.as_mut_ptr();
            ptr::copy_nonoverlapping(data, bs.data, size);
        } else {
            let layout = std::alloc::Layout::from_size_align_unchecked(size, 1);
            let ptr = std::alloc::alloc(layout);
            ptr::copy_nonoverlapping(data, ptr, size);
            bs.data = ptr;
            bs.number_of_bits_allocated = length * 8;
        }
    } else {
        bs.data = data;
        bs.number_of_bits_allocated = length * 8;
    }
}

#[no_mangle]
pub unsafe extern "C" fn rust_bitstream_destruct(bs: *mut BitStreamRust) {
    let bs = &mut *bs;
    if bs.copy_data && bs.data != bs.stack_data.as_mut_ptr() && !bs.data.is_null() {
        let size = (bs.number_of_bits_allocated / 8) as usize;
        let layout = std::alloc::Layout::from_size_align_unchecked(size, 1);
        std::alloc::dealloc(bs.data, layout);
    }
}

#[no_mangle]
pub unsafe extern "C" fn rust_bitstream_reset(bs: *mut BitStreamRust) {
    let bs = &mut *bs;
    bs.number_of_bits_used = 0;
    bs.read_offset = 0;
}

#[no_mangle]
pub unsafe extern "C" fn rust_bitstream_write_bits(
    bs: *mut BitStreamRust,
    in_byte_array: *const u8,
    mut number_of_bits_to_write: u32,
    right_aligned_bits: bool,
) {
    let bs = &mut *bs;
    if number_of_bits_to_write == 0 {
        return;
    }

    let new_bits = bs.number_of_bits_used + number_of_bits_to_write;
    if new_bits > bs.number_of_bits_allocated {
        let old_size = (bs.number_of_bits_allocated / 8) as usize;
        let mut new_size = old_size * 2;
        if new_size < (new_bits / 8 + 1) as usize {
            new_size = (new_bits / 8 + 1) as usize;
        }

        let new_layout = std::alloc::Layout::from_size_align_unchecked(new_size, 1);
        let new_ptr = std::alloc::alloc(new_layout);

        ptr::copy_nonoverlapping(bs.data, new_ptr, old_size);
        ptr::write_bytes(new_ptr.add(old_size), 0, new_size - old_size);

        if bs.copy_data && bs.data != bs.stack_data.as_mut_ptr() && !bs.data.is_null() {
            let old_layout = std::alloc::Layout::from_size_align_unchecked(old_size, 1);
            std::alloc::dealloc(bs.data, old_layout);
        }

        bs.data = new_ptr;
        bs.number_of_bits_allocated = (new_size * 8) as u32;
        bs.copy_data = true;
    }

    let number_of_bits_used_mod_8 = bs.number_of_bits_used & 7;

    if number_of_bits_used_mod_8 == 0 && (number_of_bits_to_write & 7) == 0 {
        ptr::copy_nonoverlapping(
            in_byte_array,
            bs.data.add((bs.number_of_bits_used >> 3) as usize),
            (number_of_bits_to_write >> 3) as usize,
        );
        bs.number_of_bits_used += number_of_bits_to_write;
        return;
    }

    let mut input_ptr = in_byte_array;
    while number_of_bits_to_write > 0 {
        let mut data_byte = *input_ptr;
        input_ptr = input_ptr.add(1);

        if number_of_bits_to_write < 8 && right_aligned_bits {
            data_byte <<= 8 - number_of_bits_to_write;
        }

        let write_idx = (bs.number_of_bits_used >> 3) as usize;
        let used_mod_8 = bs.number_of_bits_used & 7;

        if used_mod_8 == 0 {
            *bs.data.add(write_idx) = data_byte;
        } else {
            *bs.data.add(write_idx) |= data_byte >> used_mod_8;
            if 8 - used_mod_8 < 8 && 8 - used_mod_8 < number_of_bits_to_write {
                *bs.data.add(write_idx + 1) = data_byte << (8 - used_mod_8);
            }
        }

        if number_of_bits_to_write >= 8 {
            bs.number_of_bits_used += 8;
            number_of_bits_to_write -= 8;
        } else {
            bs.number_of_bits_used += number_of_bits_to_write;
            number_of_bits_to_write = 0;
        }
    }
}

#[no_mangle]
pub unsafe extern "C" fn rust_bitstream_read_bits(
    bs: *mut BitStreamRust,
    in_byte_array: *mut u8,
    mut number_of_bits_to_read: u32,
    align_bits_to_right: bool,
) -> bool {
    let bs = &mut *bs;
    if number_of_bits_to_read == 0 {
        return true;
    }
    if bs.read_offset + number_of_bits_to_read > bs.number_of_bits_used {
        return false;
    }

    let read_offset_mod_8 = bs.read_offset & 7;

    if read_offset_mod_8 == 0 && (number_of_bits_to_read & 7) == 0 {
        ptr::copy_nonoverlapping(
            bs.data.add((bs.read_offset >> 3) as usize),
            in_byte_array,
            (number_of_bits_to_read >> 3) as usize,
        );
        bs.read_offset += number_of_bits_to_read;
        return true;
    }

    let mut output_ptr = in_byte_array;
    ptr::write_bytes(
        in_byte_array,
        0,
        ((number_of_bits_to_read + 7) >> 3) as usize,
    );

    while number_of_bits_to_read > 0 {
        let read_idx = (bs.read_offset >> 3) as usize;
        let offset_mod_8 = bs.read_offset & 7;

        let mut data_byte = *bs.data.add(read_idx) << offset_mod_8;
        if offset_mod_8 > 0
            && offset_mod_8 < 8
            && bs.read_offset + 8 - offset_mod_8 <= bs.number_of_bits_used
        {
            data_byte |= *bs.data.add(read_idx + 1) >> (8 - offset_mod_8);
        }

        let bits_to_copy = number_of_bits_to_read.min(8);
        if bits_to_copy < 8 {
            if align_bits_to_right {
                data_byte >>= 8 - bits_to_copy;
            }
            *output_ptr = data_byte;
        } else {
            *output_ptr = data_byte;
        }
        output_ptr = output_ptr.add(1);

        bs.read_offset += bits_to_copy;
        number_of_bits_to_read -= bits_to_copy;
    }

    true
}

#[no_mangle]
pub unsafe extern "C" fn rust_bitstream_write_aligned_bytes(
    bs: *mut BitStreamRust,
    in_byte_array: *const u8,
    number_of_bytes_to_write: u32,
) {
    let bs = &mut *bs;
    bs.number_of_bits_used = (bs.number_of_bits_used + 7) & !7;
    rust_bitstream_write_bits(bs, in_byte_array, number_of_bytes_to_write * 8, false);
}

#[no_mangle]
pub unsafe extern "C" fn rust_bitstream_read_aligned_bytes(
    bs: *mut BitStreamRust,
    in_byte_array: *mut u8,
    number_of_bytes_to_read: u32,
) -> bool {
    let bs = &mut *bs;
    bs.read_offset = (bs.read_offset + 7) & !7;
    rust_bitstream_read_bits(bs, in_byte_array, number_of_bytes_to_read * 8, false)
}

#[no_mangle]
pub unsafe extern "C" fn rust_bitstream_write_bitstream(
    bs: *mut BitStreamRust,
    src_bs: *mut BitStreamRust,
    number_of_bits: u32,
) {
    let bs = &mut *bs;
    let src_bs = &mut *src_bs;
    if number_of_bits == 0 {
        return;
    }

    let saved_read_offset = src_bs.read_offset;
    let num_bytes = ((number_of_bits + 7) >> 3) as usize;
    let mut temp_buf = vec![0u8; num_bytes];

    let success = rust_bitstream_read_bits(src_bs, temp_buf.as_mut_ptr(), number_of_bits, false);
    if success {
        rust_bitstream_write_bits(bs, temp_buf.as_ptr(), number_of_bits, false);
    }

    src_bs.read_offset = saved_read_offset;
}

#[no_mangle]
pub extern "C" fn rust_get_time_ms() -> u64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap_or(std::time::Duration::ZERO)
        .as_millis() as u64
}
