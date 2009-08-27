require 'rubygems'
require 'bankjob'      # this require will pull in all the classes we need
require 'base_scraper' # this defines scraper that BpiScraper extends
require 'base64'
require 'digest/sha1'

include Bankjob        # access the namespace of Bankjob

##
# 
# CgdScapper is a scraper to Caixa Geral de Depositos bank in Portugal (www.cgd.pt).
# It follows the basic recipe for scrapers explained in BaseScraper and in the documentation.
# This bank allows the download of file with the latest 100 statements which is used by this scrapper
# to get all the information.
#
#
# CgdScraper expects the contract number without the leading zeros, access code and account number
# to be passed on the command line using --scraper-args "contract_number access_code account_number"
#  (with a space between them).
# Example:
# --scraper-args "12345 01234 000123123312"
#
#



class CgdScraper < BaseScraper
  currency "EUR"
  decimal ","
  account_number "1234567"
  account_type Statement::CHECKING
  
  
  # remove thousand separators because cause problems in some applications
  transaction_rule do |tx|
      tx.amount.gsub!('.', '')
      tx.new_balance.gsub!('.', '')
  end
  
  # download and read file
  def fetch_transactions_page(agent)
    
    login_params = { "op" =>"",
                     "requestDataSessionKey"=>"",
                     "op_param"=>"",
                     "unauthId"=>""
    }

    file_params = { "cIdParam"=>"TTggc",
                    "changeActiveAccount"=>"0",
                    "accountIndex"=>"0",
                    "filter"=>"0",
                    "maxResults"=>"100",
                    "sortOrder"=>"1",
                    "typeFilter"=>"-1",
                    "uptoDate.wasChanged"=>"1",
                    "uptoDate.day" => Time.now.day.to_s,
                    "uptoDate.month" => Time.now.month.to_s,
                    "uptoDate.year" => Time.now.year.to_s,
                    "uptoDate.hour" => Time.now.hour.to_s,
                    "uptoDate.minute" => Time.now.min.to_s
    }
    
    if (scraper_args)
      contract_number, access_code, account_number = *scraper_args
    end
    raise "Login failed for CGD Scraper - pass contract number(without the left zeros. ex. 012345 should be entered as 12345), access code and account number using -scraper_args \"contract_number <space> access_code <space> account_number\"" unless (contract_number and access_code and account_number)

    agent.user_agent_alias = 'Mac Safari'
    
    # login
    page = agent.get('https://caixadirecta.cgd.pt/CaixaDirecta/loginStart.do')
    hash_salt = page.body.scan(/doHash\(contractNumber\.value, accessCode\.value, \'(\d*?)\'/)[0][0].to_i
    login_form = page.form('loginForm')
    login_params["credentialsSessionKey"] = login_form.credentialsSessionKey
    login_params["accessCode"] = do_hash(contract_number, access_code, hash_salt)
    login_params["contractNumber"] = contract_number
    page = agent.post('https://caixadirecta.cgd.pt/CaixaDirecta/login.do', login_params)
    sleep 3 # let login servers work
    
    # get statement file
    filename = "CGD_#{file_params['uptoDate.year']}#{file_params['uptoDate.month']}#{file_params['uptoDate.day']}#{file_params['uptoDate.hour']}#{file_params['uptoDate.minute']}.csv"
    file_params["accountNumber"] = "#{account_number}+-+Conta+Extracto"
    file_params["accountLabel"] = account_number
    
    file = agent.post("https://caixadirecta.cgd.pt/CaixaDirecta/statement.do?download=statement.csv&downloadTypeP=csv", file_params) #download
    lines = file.body
    logger.debug("Lines: #{lines.size}")
    # logout
    page = agent.get('https://caixadirecta.cgd.pt/CaixaDirecta/logout.do')
    
    return lines
  end
  
  
  def parse_transactions_page(transactions_page)
    statement = create_statement
    statement.account_number = scraper_args[2]
    transactions_page.each do |line|
      
      next unless line =~ /^"\d{2}-\d{2}-\d{2}.*/ # if this line is not valid get next line 
      bits = line.gsub("\"", "").split(';')
      
      transaction = create_transaction
      transaction.date = bits[0] # Data Movimentos
      transaction.value_date = bits[1] # Data Valor
      
      size = bits.size
      if size > 6 # description is stupid enough to have ";" in it
        transaction.description = ""
        (2).upto(size - 4) { |i| transaction.description << bits[i] } # description is all fields but the three last
        transaction.amount = bits[-3].empty? ? bits[-2] : '-' + bits[-3] # find if transaction is credit(1 before last) or debit(2 before last)
        transaction.new_balance= bits[-1] # new balance is the last field
      else # normal case
        transaction.description = bits[2] # Descrição
        transaction.amount = bits[3].empty? ? bits[4] : '-' + bits[3] # find if transaction is credit(bits[4]) or debit(bits[3])
        transaction.new_balance= bits[5]
      end
      
      statement.add_transaction(transaction)
    end
  
    statement.finish(true, true)
    return statement
  end
  
  private
  
  def do_hash(user_id, password, challenge) # generate login hash
      Base64.encode64(Digest::SHA1.digest(user_id.to_s + challenge.to_s + password.to_s)).chop.chop
  end
  
end