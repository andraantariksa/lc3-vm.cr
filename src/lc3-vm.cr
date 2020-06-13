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
  AND  # Store Register
  LDR  # Unused
  STR  # Bitwise not
  RTI  # Bitwise and
  NOT  # Load indirect
  LDI  # Load register
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
  GetC  = 0x20
  Out   = 0x21
  Puts  = 0x22
  In    = 0x23
  Putsp = 0x24
  Halt  = 0x25
end

MEMORY                = Array(UInt16).new(UInt16::MAX, 0)
REGISTER_STORAGE      = Array(UInt16).new(Register::Count.value, 0)
PROGRAM_COUNTER_START = 0x3000_u16

def swap16(two_byte : UInt16) : UInt16
  (two_byte << 8) | (two_byte >> 8)
end

def sign_extend(value : UInt16, bit_count : UInt8)
  if (value >> (bit_count - 1)) & 1 != 0
    value |= (0xFFFF << bit_count)
  end

  value
end

def read_image_file(filename : String)
  if !File.file?(filename)
    raise "Invalid file"
  end

  file = File.open(filename)

  location : UInt16 = file.read_bytes(UInt16, IO::ByteFormat::BigEndian)
  twobyte : UInt16

  while true
    begin
      twobyte = file.read_bytes(UInt16, IO::ByteFormat::BigEndian)
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
    byte : UInt16 = (STDIN.raw &.read_char).not_nil!.ord.to_u16
    if byte != 0
      MEMORY[MemoryMappedRegister::KeyboardStatus.value] = 1_u16 << 15
      MEMORY[MemoryMappedRegister::KeyboardData.value] = byte
    else
      MEMORY[MemoryMappedRegister::KeyboardStatus.value] = 0
    end
  end

  MEMORY[address]
end

def write_memory(address : UInt16, value : UInt16)
  MEMORY[address] = value
end

def execute_trap(instruction : UInt16) : Bool
  output : Char
  input_charcode : UInt16
  char_location : UInt16

  quit : Bool = false
  case TrapCode.new(instruction & 0xFF)
  when TrapCode::GetC
    input_charcode = gets(1).not_nil!.byte_at(0).to_u16
    REGISTER_STORAGE[Register::R0.value] = input_charcode
  when TrapCode::Out
    output = REGISTER_STORAGE[Register::R0.value & 0xFF].unsafe_chr
    print(output)
  when TrapCode::Puts
    char_location = REGISTER_STORAGE[Register::R0.value]
    while MEMORY[char_location] != 0
      output = (MEMORY[char_location] & 0xFF).unsafe_chr
      print(output)

      char_location += 1
    end
    STDOUT.flush
  when TrapCode::In
    print("Enter a character: ")
    STDOUT.flush

    input_charcode = gets(1).not_nil!.byte_at(0).to_u16
    print(input_charcode.unsafe_chr)
    STDOUT.flush

    REGISTER_STORAGE[Register::R0.value] = input_charcode
  when TrapCode::Putsp
    char_location = REGISTER_STORAGE[Register::R0.value]
    while MEMORY[char_location] != 0
      output = (MEMORY[char_location] & 0xFF).unsafe_chr
      print(output)

      charcode_2nd = MEMORY[char_location] >> 8
      if charcode_2nd != 0
        print(charcode_2nd.unsafe_chr)
      end

      char_location += 1
    end
    STDOUT.flush
  when TrapCode::Halt
    print("HALT")
    STDOUT.flush
    quit = true
  end

  quit
end

def dispatch
  dr : UInt16
  sr : UInt16
  sr1 : UInt16
  sr2 : UInt16
  imm_flag : UInt16
  imm5 : UInt16
  base_r : UInt16
  pc_offset : UInt16
  instruction : UInt16
  operator : UInt16

  REGISTER_STORAGE[Register::ProgramCounter.value] = PROGRAM_COUNTER_START

  running : Bool = true
  while running
    instruction = read_memory(REGISTER_STORAGE[Register::ProgramCounter.value])
    REGISTER_STORAGE[Register::ProgramCounter.value] += 1
    operator = instruction >> 12

    case Instruction.new(operator)
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
    when Instruction::BR
      n_flag : UInt16 = (instruction >> 11) & 0x1
      z_flag : UInt16 = (instruction >> 10) & 0x1
      p_flag : UInt16 = (instruction >> 9) & 0x1

      pc_offset = sign_extend(instruction & 0x1FF, 9)

      if (n_flag != 0 && (REGISTER_STORAGE[Register::Conditional.value] & ConditionFlag::NEG.value) != 0) ||
         (z_flag != 0 && (REGISTER_STORAGE[Register::Conditional.value] & ConditionFlag::ZERO.value) != 0) ||
         (p_flag != 0 && (REGISTER_STORAGE[Register::Conditional.value] & ConditionFlag::POS.value) != 0)
        REGISTER_STORAGE[Register::ProgramCounter.value] += pc_offset
      end
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
    when Instruction::LDI
      dr = (instruction >> 9) & 0x7

      pc_offset = sign_extend(instruction & 0x1FF, 9)

      REGISTER_STORAGE[dr] = read_memory(read_memory(REGISTER_STORAGE[Register::ProgramCounter.value] + pc_offset))

      update_flags(dr)
    when Instruction::LDR
      dr = (instruction >> 9) & 0x7

      base_r = (instruction >> 6) & 0x7

      offset = sign_extend(instruction & 0x3F, 6)

      REGISTER_STORAGE[dr] = read_memory(REGISTER_STORAGE[base_r] + offset)

      update_flags(dr)
    when Instruction::LEA
      dr = (instruction >> 9) & 0x7

      pc_offset = sign_extend(instruction & 0x1FF, 9)

      REGISTER_STORAGE[dr] = REGISTER_STORAGE[Register::ProgramCounter.value] + pc_offset
      update_flags(dr)
    when Instruction::ST
      sr = (instruction >> 9) & 0x7

      pc_offset = sign_extend(instruction & 0x1FF, 9)

      write_memory(REGISTER_STORAGE[Register::ProgramCounter.value] + pc_offset, REGISTER_STORAGE[sr])
    when Instruction::STI
      sr = (instruction >> 9) & 0x7

      pc_offset = sign_extend(instruction & 0x1FF, 9)

      write_memory(read_memory(REGISTER_STORAGE[Register::ProgramCounter.value] + pc_offset), REGISTER_STORAGE[sr])
    when Instruction::STR
      sr = (instruction >> 9) & 0x7

      base_r = (instruction >> 6) & 0x7

      pc_offset = sign_extend(instruction & 0x3F, 6)

      # TODO
      # overflow error
      # p "adding #{REGISTER_STORAGE[base_r]} + #{pc_offset}"

      write_memory(REGISTER_STORAGE[base_r] + pc_offset, REGISTER_STORAGE[sr])
    when Instruction::TRAP
      running = !execute_trap(instruction)
    when Instruction::RES
    when Instruction::RTI
    else
      exit
    end
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

LibC.tcgetattr(stdin, pointerof(term))

term.c_iflag &= LibC::IGNBRK | LibC::BRKINT | LibC::PARMRK | LibC::ISTRIP | LibC::INLCR | LibC::IGNCR | LibC::ICRNL | LibC::IXON
term.c_lflag &= ~(LibC::ICANON | LibC::ECHO)

LibC.tcsetattr(stdin, LibC::TCSANOW, pointerof(term))

dispatch()

# Reset termios data
term.c_lflag = 0
LibC.tcsetattr(stdin, LibC::TCSANOW, pointerof(term))
