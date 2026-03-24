require 'mechanize'

FILENAME_URL_LIST = 'urls.txt'

INDEX_NAME = 1
INDEX_STATUS = 2
INDEX_CALL_NUMBER = 4

agent = Mechanize.new
agent.user_agent_alias = 'Windows Chrome'

agent.get('https://www.lib.city.chofu.tokyo.jp/')
agent.get('https://www.lib.city.chofu.tokyo.jp/totalresult') # ダミー遷移（必要な場合）

File.open(FILENAME_URL_LIST, 'r').each_line do |line|
  url = line.sub(/\A.*http/, 'http')

  page = agent.get(url) rescue next
  doc = page.parser

  title = doc.at('h2')&.text&.strip

  # --- 蔵書情報テーブル ---
  table = doc.at('table.bookInfo')
  next unless table

  puts title
  table.search('tr').each do |tr|
    name, status, call_number = tr.search('th, td').map { |td|
      td.text.strip
    }.values_at(INDEX_NAME, INDEX_STATUS, INDEX_CALL_NUMBER)

    next if status.match('状態')
    next unless status.match('在庫')

    printf("  %s: %s\n", name + (name.length == 2 ? '　' : ''), call_number)
  end
end
