class LibraryPageAgent
  attr_reader :agent

  TOP_PAGE_URL = 'https://www.lib.city.chofu.tokyo.jp/'

  def initialize
    @agent = Mechanize.new
    @agent.user_agent_alias = 'Windows Chrome'

    @agent.get(TOP_PAGE_URL)
    @agent.get(TOP_PAGE_URL + '/totalresult') # ダミー遷移（必要な場合）
  end
end

class Library
  attr_reader :name, :book_info

  def initialize(name, book_info)
    @name = name
    @book_info = book_info
  end
end

class LibraryNumber
  def initialize(name, value, unit)
    @name = name
    @value = value
    @unit = unit
  end

  def to_s
    "#{@name} #{@value}#{@unit}"
  end
end

class BookInfo
  attr_reader :call_number

  MATCH_WORD_FOR_OUT_OF_STOCK = '貸出中'

  def initialize(status_desc, call_number)
    @status_desc = status_desc
    @call_number = call_number
  end

  def out_of_stock?
    @status_desc.match(MATCH_WORD_FOR_OUT_OF_STOCK)
  end
end

class BookInfoPage
  attr_reader :url, :line_number_in_url_file

  def initialize(mechanize_page, url, line_number_in_url_file)
    @nokogiri_doc = mechanize_page&.parser
    @url = url
    @line_number_in_url_file = line_number_in_url_file
  end

  def error?
    url_display = url.length > 40 ? "#{url.slice(0, 40)}..." : url

    if invalid_url?
      @error_message = "Cannot open page at line ##{line_number_in_url_file} in #{url_display}"

      return true
    elsif no_book_info_table?
      @error_message = "Cannot find 'table.bookInfo' at line ##{line_number_in_url_file} in #{url_display}"

      return true
    end

    false
  end

  def error_message
    raise Error, "#error?() must be true to call #error_message()" unless @error_message

    @error_message
  end

  def invalid_url?
    @nokogiri_doc.nil?
  end

  def no_book_info_table?
    book_info_table.nil?
  end

  def book_title
    @nokogiri_doc.at('h2')&.text&.strip
  end

  def library_numbers
    dl = @nokogiri_doc.at('div.number dl')

    dl.css('dt').each_with_index.map { |dt, i|
      dd = dl.css('dd')[i]
      next unless dd

      name = dt.text.strip
      content = dd.text.strip.gsub(/\s+/, '')

      value = content[/\d+/]&.to_i
      unit = content.gsub(/\d+/, '')

      LibraryNumber.new(name, value, unit)
    }.compact
  end

  INDEX_NAME = 1
  INDEX_STATUS = 2
  INDEX_CALL_NUMBER = 4

  def each_library
    book_info_table.at('tbody').search('tr').each do |tr|
      name, status, call_number = tr.search('th, td').map { |td|
        td.text.strip
      }.values_at(INDEX_NAME, INDEX_STATUS, INDEX_CALL_NUMBER)

      book_info = BookInfo.new(status, call_number)

      yield Library.new(name, book_info)
    end
  end

  def book_info_table
    @nokogiri_doc.at('table.bookInfo')
  end
end

class UrlReader
  FILENAME_URL_LIST = 'urls.txt'
  MATCH_PATTERN_TO_SKIP_LINE_FOR_URL = /\A#/

  def initialize(library_page_agent)
    @agent = library_page_agent
  end

  def each_page
    File.open(FILENAME_URL_LIST, 'r').each_line.with_index(1) do |line, line_number|
      next if line.match(MATCH_PATTERN_TO_SKIP_LINE_FOR_URL)

      url = line.sub(/\A.*http/, 'http').chomp
      mechanize_page = begin
                         @agent.get(url)
                       rescue OpenSSL::SSL::SSLError, Mechanize::ResponseCodeError
                         nil
                       end

      yield BookInfoPage.new(mechanize_page, url, line_number)
    end
  end
end


require 'mechanize'
require "optparse"


lists_in_stock_only = true
displays_library_numbers = false

opts = OptionParser.new
opts.on('-a', '--all', "list all including out of stock") { |v| lists_in_stock_only = false }
opts.on('-n', '--num', "display numbers for whole libraries") { |v| displays_library_numbers = true }
opts.parse!(ARGV)

agent = LibraryPageAgent.new.agent
url_reader = UrlReader.new(agent)

url_reader.each_page do |page|
  if page.error?
    STDERR.puts page.error_message
    exit
  end

  puts page.book_title

  if displays_library_numbers
    puts "（#{page.library_numbers.join('、')}）"
  end

  page.each_library do |library|
    library_name = library.name
    book_info = library.book_info

    next if lists_in_stock_only && book_info.out_of_stock?

    library_name_display = library_name + (library_name.length == 2 ? '　' : '')
    call_number_display = book_info.out_of_stock? ? '×' : book_info.call_number
    printf("  %s: %s\n", library_name_display, call_number_display)
  end
end
