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

class BookInfoPage
  attr_reader :nokogiri_doc, :url, :line_number_in_url_file

  def initialize(mechanize_page, url, line_number_in_url_file)
    @nokogiri_doc = mechanize_page&.parser
    @url = url
    @line_number_in_url_file = line_number_in_url_file
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

      url = line.sub(/\A.*http/, 'http')
      mechanize_page = begin
                         @agent.get(url)
                       rescue OpenSSL::SSL::SSLError
                         nil
                       end

      yield BookInfoPage.new(mechanize_page, url, line_number)
    end
  end
end


require 'mechanize'
require "optparse"

INDEX_NAME = 1
INDEX_STATUS = 2
INDEX_CALL_NUMBER = 4

MATCH_WORD_FOR_OUT_OF_STOCK = '貸出中'


lists_in_stock_only = true

opts = OptionParser.new
opts.on('-a', '--all', "list all including out of stock") { |v| lists_in_stock_only = false }
opts.parse!(ARGV)

agent = LibraryPageAgent.new.agent
url_reader = UrlReader.new(agent)

url_reader.each_page do |page|
  doc = page.nokogiri_doc

  unless doc
    line_number = page.line_number_in_url_file
    url = page.url

    STDERR.puts "Cannot open page at line ##{line_number} in #{url.ljust(40)}..."
    exit
  end

  book_title = doc.at('h2')&.text&.strip

  # --- 蔵書情報テーブル ---
  table = doc.at('table.bookInfo')

  unless table
    line_number = page.line_number_in_url_file
    url = page.url

    STDERR.puts "Cannot find 'table.bookInfo' at line ##{line_number} in #{url.ljust(40)}..."
    exit
  end

  puts book_title

  table.at('tbody').search('tr').each do |tr|
    name, status, call_number = tr.search('th, td').map { |td|
      td.text.strip
    }.values_at(INDEX_NAME, INDEX_STATUS, INDEX_CALL_NUMBER)

    is_out_of_stock = status.match(MATCH_WORD_FOR_OUT_OF_STOCK)
    next if lists_in_stock_only && is_out_of_stock

    name_display = name + (name.length == 2 ? '　' : '')
    call_number_display = is_out_of_stock ? '×' : call_number
    printf("  %s: %s\n", name_display, call_number_display)
  end
end
