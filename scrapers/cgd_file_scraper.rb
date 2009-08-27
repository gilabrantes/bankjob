require 'rubygems'
require 'bankjob'      # this require will pull in all the classes we need
require 'base_scraper' # this defines scraper that BpiScraper extends

include Bankjob        # access the namespace of Bankjob

##
# 
# CgdFileScapper is a scraper to files that were manually downloaded from Caixa Geral de Depositos bank in Portugal (www.cgd.pt).
# It is userfull when you already have the raw TSV or CSV files and when they are not available for download anymore.
# It simply opens the provived file and feed it to the statement generator as expected.
#
#
# CgdScraper expects the absolute file path, file type (which must be either 'csv' or 'tsv') and account number
# to be passed on the command line using --scraper-args "/absolute/file/path file_type account_number"
#  (with a space between them).
# Example:
# --scraper-args "/home/slitz/20090502.csv csv 000123123312"
#
#


class CgdFileScraper < BaseScraper
  currency "EUR"
  decimal ","
  account_number "1234567"
  account_type Statement::CHECKING
  
  
  # remove thousand separators
  transaction_rule do |tx|
      tx.amount.gsub!('.', '')
      tx.new_balance.gsub!('.', '')
  end
  
  # download and read file
  def fetch_transactions_page(agent)
    
    
    if (scraper_args)
      path, file_type, account_number = *scraper_args
    end
    raise "Login failed for CGD Scraper - pass absolute path, file_type ('csv' or 'tsv'), and account number using -scraper_args \"absolute_path <space> file_type <space> account_number\"" unless (path and file_type and account_number)

    f = File.open(path)
    lines = f.readlines
    f.close

    return lines
  end
  
  
  def parse_transactions_page(transactions_page)
    statement = create_statement
    file_type = scraper_args[1]
    statement.account_number = scraper_args[2]
    transactions_page.each do |line|
      
      # format specific stuff
      if file_type == "csv"
        next unless line =~ /^"\d{2}-\d{2}-\d{2}.*/ # if this line is not valid get next line 
        bits = line.gsub("\"", "").split(';')
      elsif file_type == "tsv"
        next unless line =~ /^\d{2}-\d{2}-\d{2}.*/ # if this line is not valid get next line 
        bits = line.split("\t")
      else
        raise "File type not know. Please use either 'tsv' or 'csv' files."
      end
      
      transaction = create_transaction
      transaction.date = bits[0] # Data Movimentos
      transaction.value_date = bits[1] # Data Valor
      
      size = bits.size
      if file_type == "csv" and size > 6 # csv files description is stupid enough to have ";" in it
        transaction.description = ""
        (2).upto(size - 4) { |i| transaction.description << bits[i] } # description is all fields but the three last
        transaction.amount = bits[-3].empty? ? bits[-2] : '-' + bits[-3] # find if transaction is credit(1 before last) or debit(2 before last)
        transaction.new_balance= bits[-1] # new balance is the last field
      else # normal case
        transaction.description = bits[2] # Descrição
        transaction.amount = bits[3].nil? ? bits[4] : '-' + bits[3] # find if transaction is credit(bits[4]) or debit(bits[3])
        transaction.new_balance= bits[5]
      end
      
      statement.add_transaction(transaction)
    end
  
    statement.finish(true, true)
    return statement
  end
  
end