#!/usr/bin/env ruby
require 'bundler'
require 'net/http'
require 'json'
require 'pry'
require 'fileutils'
require 'nokogiri'

TOP_FOLDER='o7sbfj90zpbal'
API_URL='http://www.mediafire.com/api/1.4/folder/get_content.php'
STATIC_PARAMS = {
  :r => 'nmqs',
  :response_format=>'json'
}

COOKIE='__cfduid=XXXXXXXXXXXXXXXXXXXXXXXXX; ukey=dXXXXXXXXXXXXXXXXXb5rt; currenturl=%2F; user=XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX; session=xxxxxxxxxxxxxxxxxxxxxxxxx; skey=xxxxxxxxxxxxxxxxxxxxxxxx; storageupsellshown=0; mfcurrentFolder=myfiles;'
# get your cookies with the chrome inspector, see screenshot.png

class MediaFire
  class Folder
    attr_accessor :folderkey, :name, :subfolders, :files, :parent
    def initialize(folderkey: nil,
                   name: nil,
                   parent: nil
                  )
      @folderkey = folderkey
      @name = name
      @parent = parent
      @subfolders = []
      @files = []
    end
  end
  class File
    attr_accessor :name, :url, :parent
    def initialize(name: nil,
                   url: nil,
                   parent: nil
                  )
      @name = name
      @url = url
      @parent = parent
    end
  end
end


def fetch(uri_str, limit = 10)
  puts "fetch:#{uri_str} #{limit}"
  raise ArgumentError, 'HTTP redirect too deep' if limit == 0

  url = URI.parse(uri_str)
  base = "#{url.scheme}://#{url.host}"
  req = Net::HTTP::Get.new(url.path, {'Cookie' => COOKIE,
                                      'User-Agent' => 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/63.0.3239.132 Safari/537.36'
                                     })
  response = Net::HTTP.start(url.host, url.port) { |http| http.request(req) }
  case response
  when Net::HTTPSuccess
  then
    response
  when Net::HTTPRedirection
  then
    fetch(base + response['location'], limit - 1)
  else
    response.error!
  end
end

def media_fire_get(folder, type)
  uri = URI(API_URL)
  params = STATIC_PARAMS.clone
  params[:folder_key] = folder.folderkey
  params[:content_type] = type

  uri.query = URI.encode_www_form(params)
  res = Net::HTTP.get_response(uri)
  res.is_a?(Net::HTTPSuccess) ? JSON.parse(res.body)['response'] : nil
end

def get_folder_subfolders(folder)
  res = media_fire_get(folder,'folders')
  res['folder_content']['folders'].each do |subfolder|
    folder.subfolders.push(MediaFire::Folder.new(
                            folderkey: subfolder['folderkey'],
                            name: subfolder['name'],
                            parent: folder
                          )
                          )
  end
end

def get_folder_files(folder)
  res = media_fire_get(folder,'files')
  res['folder_content']['files'].each do |file|
    folder.files.push(MediaFire::File.new(
                       name: file['filename'],
                       url: file['links']['normal_download'],
                       parent: folder
                     )
                     )
  end
end

def get_folder_contents(folder)
  get_folder_subfolders(folder)
  get_folder_files(folder)
end

def download_folder_contents(folder)
  folder.files.each do |file|
    parent = file.parent
    path = []
    until parent.nil?
      path.push(parent.name)
      parent = parent.parent
    end
    filename = "#{path.reverse.join('/')}/#{file.name}"
    FileUtils.mkdir_p(path.reverse.join('/'))
    unless File.exists?(filename) and File.size(filename) > 16384
      res = fetch(file.url).body
      doc = Nokogiri::HTML(res)
      file_url = /(http.*)\"/.match(doc.css('div.download_link')[0].text)[1] # use this regex when you use a cookie
      #    file_url = doc.css('a.DownloadButtonAd-startDownload')[0]['href'] rescue nil # the urls are here when you don't use a cookie to login
      res = fetch(file_url).body
      fd = File.open(filename, 'w+')
      fd.write(res)
      fd.close
      puts "wrote #{res.length} to #{filename}"
    else
      puts "#{filename} is cached"
    end
  end
end

def process_folder(parent_folder)
  get_folder_contents(parent_folder)
  download_folder_contents(parent_folder)
  parent_folder.subfolders.each do |folder|
    process_folder(folder)
  end
end

top_folder = MediaFire::Folder.new(folderkey: TOP_FOLDER)
top_folder.name = 'downloaded'
process_folder(top_folder)
p top_folder
