enum Register : UInt16
  R0
  R1
  R2
  R3
  R4
  R5
  R6
  R7
  ProgramCounter
  Conditional
  Count
end

enum Instruction : UInt16
  BR   # Branch
  ADD  # Add
  LD   # Load
  ST   # Store
  JSR  # Jump register
  STR  # Store Register
  RTI  # Unused
  NOT  # Bitwise not
  AND  # Bitwise and
  LDI  # Load indirect
  STI  # Store indirect
  JMP  # Jump
  RES  # Reserved (Unused)
  LEA  # Load effective address
  TRAP # Execute trap
end

enum ConditionFlag : UInt16
  POS  = 1 << 0
  ZERO = 1 << 1
  NEG  = 1 << 2
end

enum MemoryMappedRegister : UInt16
  KeyboardStatus = 0xFE00
  KeyboardData   = 0xFE02
end

enum TrapCode : UInt16
  Getc  = 0x20
  Out   = 0x21
  Puts  = 0x22
  In    = 0x23
  Putsp = 0x24
  Halt  = 0x25
end

MEMORY                = Array(UInt16).new(UInt16::MAX, 0)
REGISTER_STORAGE      = Array(UInt16).new(UInt16::MAX, 0)
PROGRAM_COUNTER_START = 0x3000_u16

macro instruction
  
end

def swap16(two_byte : UInt16) : UInt16
  (two_byte << 8) | (two_byte >> 8)
end

def sign_extend(value : UInt16, bit_count : UInt8)
  if (value >> (bit_count - 1)) & 1 == 1
    value |= (0xFFFF << bit_count)
  end

  value
end

def read_image_file(filename : String)
  if !File.file?(filename)
    raise "Invalid file"
  end

  file = File.open(filename)

  location : UInt16 = file.read_bytes(UInt16, IO::ByteFormat::LittleEndian)
  twobyte : UInt16

  while true
    begin
      twobyte = file.read_bytes(UInt16)
    rescue IO::EOFError
      break
    end
    MEMORY[location] = twobyte
    location += 1
  end
end

def update_flags(register_nth : UInt16)
  if REGISTER_STORAGE[register_nth] == 0
    REGISTER_STORAGE[Register::Conditional.value] = ConditionFlag::ZERO.value
  elsif REGISTER_STORAGE[register_nth] >> 15 == 1
    REGISTER_STORAGE[Register::Conditional.value] = ConditionFlag::NEG.value
  else
    REGISTER_STORAGE[Register::Conditional.value] = ConditionFlag::POS.value
  end
end

def read_memory(address : UInt16) : UInt16
  if address == MemoryMappedRegister::KeyboardStatus.value
    byte : Char = (STDIN.raw &.read_char).not_nil!
    if byte == 0
      MEMORY[MemoryMappedRegister::KeyboardStatus.value] = 1u16 << 15
      MEMORY[MemoryMappedRegister::KeyboardData.value] = byte.to_u16
    else
      MEMORY[MemoryMappedRegister::KeyboardStatus.value] = 0
    end
  end
  MEMORY[address]
end

def write_memory(index : UInt16, value : UInt16)
  MEMORY[index] = value
end

def execute_trap(instruction : UInt16)
  quit : Bool = false
  case instruction & 0xFF
  when Trap::Getc
    input_char : UInt16 = gets(1).not_nil!.byte_at(0).to_u16
    REGISTER_STORAGE[Register::R0.value] = input_char
  when Trap::Out
    output : Char = REGISTER_STORAGE[Register::R0.value & 0xFF].to_c
    print(output)
  when Trap::Puts
    char_location : UInt16 = REGISTER_STORAGE[Register::R0.value]
    while MEMORY[char_location] != 0
      output : Char = (MEMORY[char_location] & 0xFF).to_c
      print(output)

      char_location += 1
    end
    flush()
  when Trap::In
    print("Enter a character: ")
    flush()

    input_char : UInt16 = gets(1).not_nil!.byte_at(0).to_u16
    print(input_char.to_c)
    flush()

    REGISTER_STORAGE[Register::R0.value] = input_char
  when Trap::Putsp
  end
end

def dispatch
  REGISTER_STORAGE[Register::ProgramCounter.value] = PROGRAM_COUNTER_START

  dr : UInt16
  sr : UInt16
  sr1 : UInt16
  sr2 : UInt16
  imm_flag : UInt16
  imm5 : UInt16
  base_r : UInt16
  pc_offset : UInt16

  running : Bool = true
  while running
    instruction : UInt16 = read_memory(REGISTER_STORAGE[Register::ProgramCounter.value])
    operator : UInt16 = instruction >> 12

    case operator
    when Instruction::BR
      n_flag : UInt16 = (instruction >> 11) & 0x1
      z_flag : UInt16 = (instruction >> 10) & 0x1
      p_flag : UInt16 = (instruction >> 19) & 0x1

      pc_offset = sign_extend(instruction & 0x1FF, 9)

      if (n_flag != 0 && (REGISTER_STORAGE[Register::Conditional.value] & ConditionFlag::NEG.value) != 0) ||
         (z_flag != 0 && (REGISTER_STORAGE[Register::Conditional.value] & ConditionFlag::ZERO.value) != 0) ||
         (p_flag != 0 && (REGISTER_STORAGE[Register::Conditional.value] & ConditionFlag::POS.value) != 0)
        REGISTER_STORAGE[Register::ProgramCounter.value] += pc_offset
      end
    when Instruction::ADD
      dr = (instruction >> 9) & 0x7
      sr1 = (instruction >> 6) & 0x7
      imm_flag = (instruction >> 5) & 0x1

      if imm_flag != 0
        imm5 = sign_extend(instruction & 0x1F, 5)
        REGISTER_STORAGE[dr] = REGISTER_STORAGE[sr1] + imm5
      else
        sr2 = instruction & 0x7
        REGISTER_STORAGE[dr] = REGISTER_STORAGE[sr1] + REGISTER_STORAGE[sr2]
      end

      update_flags(dr)
    when Instruction::AND
      dr = (instruction >> 9) & 0x7
      sr1 = (instruction >> 6) & 0x7
      imm_flag = (instruction >> 5) & 0x1

      if imm_flag != 0
        imm5 = sign_extend(instruction & 0x1F, 5)
        REGISTER_STORAGE[dr] = REGISTER_STORAGE[sr1] & imm5
      else
        sr2 = instruction & 0x7
        REGISTER_STORAGE[dr] = REGISTER_STORAGE[sr1] & REGISTER_STORAGE[sr2]
      end

      update_flags(dr)
    when Instruction::NOT
      dr = (instruction >> 9) & 0x7
      sr = (instruction >> 6) & 0x7

      REGISTER_STORAGE[dr] = ~REGISTER_STORAGE[dr]
      update_flags(dr)
    when Instruction::JMP
      base_r = (instruction >> 6) & 0x7
      REGISTER_STORAGE[Register::ProgramCounter.value] = REGISTER_STORAGE[base_r]
    when Instruction::JSR
      REGISTER_STORAGE[Register::R7.value] = REGISTER_STORAGE[Register::ProgramCounter.value]

      imm_flag = (instruction >> 11) & 0x1

      if imm_flag != 0
        pc_offset = sign_extend(instruction & 0x7FF, 11)

        REGISTER_STORAGE[Register::ProgramCounter.value] += pc_offset
      else
        base_r = (instruction >> 6) & 0x7
        REGISTER_STORAGE[Register::ProgramCounter.value] = REGISTER_STORAGE[base_r]
      end
    when Instruction::LD
      dr = (instruction >> 9) & 0x7
      pc_offset = sign_extend(instruction & 0x1FF, 9)

      REGISTER_STORAGE[dr] = read_memory(REGISTER_STORAGE[Register::ProgramCounter.value] + pc_offset)

      update_flags(dr)
    when Instruction::ST
    when Instruction::STR
    when Instruction::TRAP
    when Instruction::RES
    when Instruction::RTI
    else
      exit
    end

    REGISTER_STORAGE[Register::ProgramCounter.value] += 1
  end
end

if ARGV.size == 0
  puts "lc3 [image-file1] ..."
  exit
end

filenames = ARGV
filenames.each { |filename| read_image_file(filename) }

stdin : Int32 = 0

# Set Termios
term : LibC::Termios = LibC::Termios.new
term.c_iflag &= LibC::IGNBRK | LibC::BRKINT | LibC::PARMRK | LibC::ISTRIP | LibC::INLCR | LibC::IGNCR | LibC::ICRNL | LibC::IXON
term.c_lflag &= ~(LibC::ICANON | LibC::ECHO)

dispatch()

# Reset termios data
LibC.tcsetattr(stdin, LibC::TCSANOW, pointerof(term))
